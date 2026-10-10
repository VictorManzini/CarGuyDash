import Foundation
import Observation

/// Color zones along a gauge's scale.
nonisolated enum GaugeColor: Equatable {
    case blue, green, yellow, orange, red

    /// Vivid, fully opaque colors (0...255).
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .blue: (0x29, 0x79, 0xFF)
        case .green: (0x00, 0xE6, 0x76)
        case .yellow: (0xFF, 0xEA, 0x00)
        case .orange: (0xFF, 0x91, 0x00)
        case .red: (0xFF, 0x17, 0x44)
        }
    }
}

/// A sensor's scale on the gauges, always in the sensor's internal unit (°C, kPa, km/h).
/// Blue below `normalLow`, green to yellow across the normal band, orange halfway to the redline, red from `redline`.
nonisolated struct GaugeRange: Codable, Equatable {
    var min: Double
    var max: Double
    var normalLow: Double
    var normalHigh: Double
    var redline: Double

    /// RPM and coolant: the owner's values. Every other sensor gets the whole range its formula can give
    /// (no made-up engine limits): normal = all of it, redline = max.
    static func standard(for sensor: Sensor) -> GaugeRange {
        switch sensor {
        case .rpm: return GaugeRange(min: 0, max: 7000, normalLow: 0, normalHigh: 6000, redline: 6500)
        case .coolantTemp: return GaugeRange(min: 40, max: 130, normalLow: 90, normalHigh: 105, redline: 115)
        default:
            // Every formula grows with its bytes: all 0x00 = lowest value, all 0xFF = highest.
            let low = sensor.decode([0, 0]) ?? 0
            let high = sensor.decode([255, 255]) ?? 0
            return GaugeRange(min: low, max: high, normalLow: low, normalHigh: high, redline: high)
        }
    }

    /// The boost: the manifold's formula range (0–255 kPa) moved down by one atmosphere.
    // ponytail: fixed 101 kPa shift; the real atmosphere varies a few kPa, fine for a dial scale.
    static func standard(for source: GaugeSource) -> GaugeRange {
        switch source {
        case .sensor(let sensor): standard(for: sensor)
        case .boost: GaugeRange(min: -101, max: 154, normalLow: -101, normalHigh: 154, redline: 154)
        }
    }

    /// Why this range cannot be saved, or nil when it can: min ≤ normalLow ≤ normalHigh ≤ redline ≤ max, and min < max.
    /// Equal neighbours are allowed: normalLow = min means no blue (RPM), normalHigh = redline = max means no orange or red.
    var problem: String? {
        if min >= max { return "Min must be below max." }
        if normalLow < min { return "Normal low can't be below min." }
        if normalHigh < normalLow { return "Normal high can't be below normal low." }
        if redline < normalHigh { return "Redline can't be below normal high." }
        if redline > max { return "Redline can't be above max." }
        return nil
    }

    /// Where `value` sits on the scale: 0 = min, 1 = max, clamped.
    func fraction(_ value: Double) -> Double {
        guard max > min else { return 0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }

    /// Fixed color stops along the scale (0...1), shared by the bar and arc gradients; red from the redline to max.
    /// No blue when the normal band starts at the minimum (RPM starts green).
    var stops: [(color: GaugeColor, at: Double)] {
        let blue: [(color: GaugeColor, at: Double)] = normalLow > min ? [(.blue, 0)] : []
        return blue + [(.green, fraction(normalLow)), (.yellow, fraction(normalHigh)),
                       (.orange, fraction((normalHigh + redline) / 2)), (.red, fraction(redline))]
    }

    /// The color of the last stop at or before `value`: blue below normalLow, green in the normal band,
    /// yellow from normalHigh, orange from halfway to the redline, red from the redline.
    func color(at value: Double) -> GaugeColor {
        let at = fraction(value)
        return stops.last { $0.at <= at }?.color ?? stops[0].color
    }

    /// The gradient's color at `value`, mixed smoothly between the two stops around it (0...255).
    func rgb(at value: Double) -> (r: Double, g: Double, b: Double) {
        let at = fraction(value)
        guard let next = stops.firstIndex(where: { $0.at > at }), next > 0 else { return color(at: value).rgb }
        let (a, b) = (stops[next - 1], stops[next])
        let t = (at - a.at) / (b.at - a.at)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return (mix(a.color.rgb.r, b.color.rgb.r), mix(a.color.rgb.g, b.color.rgb.g), mix(a.color.rgb.b, b.color.rgb.b))
    }

    /// The same range in the chosen units, for the labels on screen.
    func converted(for sensor: Sensor, _ units: Units) -> GaugeRange {
        let c = { sensor.displayValue($0, units) }
        return GaugeRange(min: c(min), max: c(max), normalLow: c(normalLow), normalHigh: c(normalHigh), redline: c(redline))
    }

    /// The opposite of `converted`: a range typed in the chosen units, back in the internal unit.
    func convertedBack(for sensor: Sensor, _ units: Units) -> GaugeRange {
        let c = { sensor.internalValue($0, units) }
        return GaugeRange(min: c(min), max: c(max), normalLow: c(normalLow), normalHigh: c(normalHigh), redline: c(redline))
    }
}

/// Ranges the user changed, saved on the iPhone (UserDefaults, as JSON). Any other one uses `standard(for:)`.
@Observable final class GaugeRangeSettings {
    /// Key = the source's raw value (sensor PID, or "boost").
    private(set) var saved: [String: GaugeRange]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.data(forKey: "gauge.ranges")
            .flatMap { try? JSONDecoder().decode([String: GaugeRange].self, from: $0) } ?? [:]
    }

    func range(for source: GaugeSource) -> GaugeRange {
        saved[source.rawValue] ?? .standard(for: source)
    }

    func set(_ range: GaugeRange, for source: GaugeSource) {
        saved[source.rawValue] = range
        defaults.set(try? JSONEncoder().encode(saved), forKey: "gauge.ranges")
    }

    /// Saves a range typed in the chosen units, converted to the internal unit.
    /// Returns why it was not saved (see `GaugeRange.problem`), or nil when it was.
    @discardableResult
    func save(typed: GaugeRange, for source: GaugeSource, units: Units) -> String? {
        if let problem = typed.problem { return problem }
        set(typed.convertedBack(for: source.sensor, units), for: source)
        return nil
    }

    /// Back to `standard(for:)`.
    func reset(_ source: GaugeSource) {
        saved[source.rawValue] = nil
        defaults.set(try? JSONEncoder().encode(saved), forKey: "gauge.ranges")
    }
}
