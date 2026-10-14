import Foundation

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

/// RPM's zones (only RPM has them): blue below `normalLow`, green across the normal band, yellow from `normalHigh`,
/// orange halfway to the redline, red from `redline`. The race dash shift lights run from `normalHigh` to `redline`.
nonisolated struct RPMZones: Codable, Equatable {
    var normalLow: Double
    var normalHigh: Double
    var redline: Double
}

/// A sensor's scale on the gauges, always in the sensor's internal unit (°C, kPa, km/h).
/// RPM has `rpm` zones. Every other source may have a `target`: blue at min, pure green at the target,
/// then yellow, orange and red exactly at max. No target = all green.
nonisolated struct GaugeRange: Equatable {
    var min: Double
    var max: Double
    /// Every source except RPM: where the gauge is pure green. nil = all green.
    var target: Double?
    /// RPM only; nil for every other source.
    var rpm: RPMZones?

    /// RPM and coolant: the owner's values. Every other sensor gets the whole range its formula can give
    /// and no target (no made-up engine limits): all green.
    static func standard(for sensor: Sensor) -> GaugeRange {
        switch sensor {
        case .rpm: return GaugeRange(min: 0, max: 7000, rpm: RPMZones(normalLow: 0, normalHigh: 6000, redline: 6500))
        case .coolantTemp: return GaugeRange(min: 40, max: 115, target: 95)
        default:
            // Every formula grows with its bytes: all 0x00 = lowest value, all 0xFF = highest.
            return GaugeRange(min: sensor.decode([0, 0]) ?? 0, max: sensor.decode([255, 255]) ?? 0)
        }
    }

    /// The boost: the manifold's formula range (0–255 kPa) moved down by one atmosphere.
    // ponytail: fixed 101 kPa shift; the real atmosphere varies a few kPa, fine for a dial scale.
    static func standard(for source: GaugeSource) -> GaugeRange {
        switch source {
        case .sensor(let sensor): standard(for: sensor)
        case .boost: GaugeRange(min: -101, max: 154)
        }
    }

    /// Keeps only what `source` uses: RPM its zones (the default ones if missing) and no target; every other source no zones.
    /// A range saved before targets (five values) on a source other than RPM arrives with zones and is converted:
    /// max = the old redline (red stays where it was), target = the middle of the old normal band,
    /// or no target when that band was the whole scale (it was all green).
    func fitted(to source: GaugeSource) -> GaugeRange {
        if source == .sensor(.rpm) {
            return GaugeRange(min: min, max: max, rpm: rpm ?? Self.standard(for: source).rpm)
        }
        guard let old = rpm else { return GaugeRange(min: min, max: max, target: target) }
        let wholeScale = old.normalLow <= min && old.normalHigh >= max
        // A redline at the min would leave an empty scale: keep the old max then.
        return GaugeRange(min: min, max: old.redline > min ? old.redline : max,
                          target: wholeScale ? nil : (old.normalLow + old.normalHigh) / 2)
    }

    /// Why this range cannot be saved, or nil when it can. Always min < max.
    /// RPM: min ≤ normalLow ≤ normalHigh ≤ redline ≤ max (equal neighbours allowed: normalLow = min means no blue).
    /// Others: min ≤ target ≤ max.
    var problem: String? {
        if min >= max { return "Min must be below max." }
        if let rpm {
            if rpm.normalLow < min { return "Normal low can't be below min." }
            if rpm.normalHigh < rpm.normalLow { return "Normal high can't be below normal low." }
            if rpm.redline < rpm.normalHigh { return "Redline can't be below normal high." }
            if rpm.redline > max { return "Redline can't be above max." }
        }
        if let target {
            if target < min { return "Target can't be below min." }
            if target > max { return "Target can't be above max." }
        }
        return nil
    }

    // Temporary: the colors and the range editor still use the five values; they move to target and zones next.
    init(min: Double, max: Double, target: Double? = nil, rpm: RPMZones? = nil) {
        self.min = min
        self.max = max
        self.target = target
        self.rpm = rpm
    }

    init(min: Double, max: Double, normalLow: Double, normalHigh: Double, redline: Double) {
        self.init(min: min, max: max, rpm: RPMZones(normalLow: normalLow, normalHigh: normalHigh, redline: redline))
    }

    var normalLow: Double { rpm?.normalLow ?? target ?? min }
    var normalHigh: Double { rpm?.normalHigh ?? target ?? max }
    var redline: Double { rpm?.redline ?? max }

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
        mapped { sensor.displayValue($0, units) }
    }

    /// The opposite of `converted`: a range typed in the chosen units, back in the internal unit.
    func convertedBack(for sensor: Sensor, _ units: Units) -> GaugeRange {
        mapped { sensor.internalValue($0, units) }
    }

    /// Every value through `c`: min, max, target and the zones.
    private func mapped(_ c: (Double) -> Double) -> GaugeRange {
        GaugeRange(min: c(min), max: c(max), target: target.map(c),
                   rpm: rpm.map { RPMZones(normalLow: c($0.normalLow), normalHigh: c($0.normalHigh), redline: c($0.redline)) })
    }
}

/// Saved as `min`, `max` and, when set, `target` and `rpm`. A range saved before targets has five flat values
/// (`min`, `max`, `normalLow`, `normalHigh`, `redline`): it loads with those as zones, and `fitted(to:)` converts it
/// once the source is known.
nonisolated extension GaugeRange: Codable {
    private enum CodingKeys: String, CodingKey { case min, max, target, rpm }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let zones = try container.decodeIfPresent(RPMZones.self, forKey: .rpm)
        self.init(min: try container.decode(Double.self, forKey: .min),
                  max: try container.decode(Double.self, forKey: .max),
                  target: try container.decodeIfPresent(Double.self, forKey: .target),
                  // The old flat values have RPMZones' own key names, so they decode straight from this level.
                  rpm: zones ?? (try? RPMZones(from: decoder)))
    }
}
