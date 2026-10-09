import Foundation
import Observation

/// Color zones along a gauge's scale.
nonisolated enum GaugeColor: Equatable {
    case blue, green, yellow, red
}

/// A sensor's scale on the gauges, always in the sensor's internal unit (°C, kPa, km/h).
/// Blue below `normalLow`, green to yellow across the normal band, red from `redline`.
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
        case .coolantTemp: return GaugeRange(min: 40, max: 130, normalLow: 90, normalHigh: 105, redline: 105)
        default:
            // Every formula grows with its bytes: all 0x00 = lowest value, all 0xFF = highest.
            let low = sensor.decode([0, 0]) ?? 0
            let high = sensor.decode([255, 255]) ?? 0
            return GaugeRange(min: low, max: high, normalLow: low, normalHigh: high, redline: high)
        }
    }

    /// Where `value` sits on the scale: 0 = min, 1 = max, clamped.
    func fraction(_ value: Double) -> Double {
        guard max > min else { return 0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }

    /// Fixed color stops along the scale (0...1), shared by the bar and arc gradients.
    /// No blue when the normal band starts at the minimum (RPM starts green).
    var stops: [(color: GaugeColor, at: Double)] {
        let blue: [(color: GaugeColor, at: Double)] = normalLow > min ? [(.blue, 0)] : []
        return blue + [(.green, fraction(normalLow)), (.yellow, fraction(normalHigh)), (.red, fraction(redline))]
    }

    /// The color of the last stop at or before `value`: blue below normalLow, green in the normal band,
    /// yellow from normalHigh, red from the redline.
    func color(at value: Double) -> GaugeColor {
        let at = fraction(value)
        return stops.last { $0.at <= at }?.color ?? stops[0].color
    }

    /// The same range in the chosen units, for the labels on screen.
    func converted(for sensor: Sensor, _ units: Units) -> GaugeRange {
        let c = { sensor.displayValue($0, units) }
        return GaugeRange(min: c(min), max: c(max), normalLow: c(normalLow), normalHigh: c(normalHigh), redline: c(redline))
    }
}

/// Ranges the user changed, saved on the iPhone (UserDefaults, as JSON). Any other sensor uses `standard(for:)`.
@Observable final class GaugeRangeSettings {
    /// Key = sensor PID.
    private(set) var saved: [String: GaugeRange]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saved = defaults.data(forKey: "gauge.ranges")
            .flatMap { try? JSONDecoder().decode([String: GaugeRange].self, from: $0) } ?? [:]
    }

    func range(for sensor: Sensor) -> GaugeRange {
        saved[sensor.rawValue] ?? .standard(for: sensor)
    }

    func set(_ range: GaugeRange, for sensor: Sensor) {
        saved[sensor.rawValue] = range
        defaults.set(try? JSONEncoder().encode(saved), forKey: "gauge.ranges")
    }
}
