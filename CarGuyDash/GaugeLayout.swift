import Foundation
import Observation

/// What one gauge shows: a sensor, or the boost (manifold − atmospheric), which is read from the manifold pressure (0B).
/// Raw value = the sensor's PID, or "boost": saved in the layout and used as the key of the saved range.
nonisolated enum GaugeSource: Hashable, Codable, RawRepresentable {
    case sensor(Sensor)
    case boost

    init?(rawValue: String) {
        if rawValue == "boost" {
            self = .boost
        } else if let sensor = Sensor(rawValue: rawValue) {
            self = .sensor(sensor)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .sensor(let sensor): sensor.rawValue
        case .boost: "boost"
        }
    }

    /// Saved as the raw value ("0C", "boost").
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let source = GaugeSource(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown gauge source \(raw)"))
        }
        self = source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Every sensor of the enum (all of them are numbers), then the boost.
    static let all: [GaugeSource] = Sensor.allCases.map { .sensor($0) } + [.boost]

    /// The sensor that is polled and gives the unit and the decimals: the boost uses the manifold pressure.
    var sensor: Sensor {
        switch self {
        case .sensor(let sensor): sensor
        case .boost: .manifoldPressure
        }
    }

    var name: String { self == .boost ? "Boost" : sensor.name }
}

nonisolated enum GaugeStyle: String, Codable, CaseIterable {
    case analog = "Analog", digital = "Digital", bar = "Bar", arc = "Arc"
}

nonisolated struct GaugeSlot: Codable, Equatable {
    var source: GaugeSource
    var style: GaugeStyle
}

/// How many gauges are shown (1 to 6) and what each one shows, in what style.
/// All six slots are always kept, so lowering the count and raising it again brings the same gauges back.
nonisolated struct GaugeLayout: Codable, Equatable {
    static let maxCount = 6

    var slots: [GaugeSlot]
    private var storedCount: Int
    /// Locked to 1...6.
    var count: Int {
        get { Swift.min(Swift.max(storedCount, 1), Self.maxCount) }
        set { storedCount = Swift.min(Swift.max(newValue, 1), Self.maxCount) }
    }

    private enum CodingKeys: String, CodingKey {
        case slots, storedCount = "count"
    }

    init(slots: [GaugeSlot], count: Int) {
        self.slots = slots
        storedCount = count
        self.count = count
    }

    static let standard = GaugeLayout(slots: [
        GaugeSlot(source: .sensor(.rpm), style: .analog),
        GaugeSlot(source: .sensor(.coolantTemp), style: .arc),
        GaugeSlot(source: .sensor(.oilTemp), style: .arc),
        GaugeSlot(source: .boost, style: .arc),
        GaugeSlot(source: .sensor(.intakeAirTemp), style: .arc),
        GaugeSlot(source: .sensor(.moduleVoltage), style: .arc),
    ], count: 6)

    /// The slots on screen: the first `count`.
    var visibleSlots: [GaugeSlot] { Array(slots.prefix(count)) }

    /// What polling asks: the sensors of the visible gauges, each once, in slot order (the boost asks 0B),
    /// without the ones the car lacks. `supported` nil = discovery failed: all of them.
    /// At most 6, since there are at most 6 gauges.
    func sensorsToPoll(supported: Set<Int>?) -> [Sensor] {
        var sensors: [Sensor] = []
        for slot in visibleSlots where !sensors.contains(slot.source.sensor) {
            sensors.append(slot.source.sensor)
        }
        guard let supported else { return sensors }
        return sensors.filter { supported.contains(Int($0.rawValue, radix: 16) ?? -1) }
    }
}

/// The layout the user picked, saved on the iPhone (UserDefaults, as JSON).
@Observable final class GaugeLayoutSettings {
    var layout: GaugeLayout {
        didSet {
            defaults.set(try? JSONEncoder().encode(layout), forKey: "gauge.layout")
            onChange?()
        }
    }
    /// Called after every change; the scanner uses it to wake a polling loop that had nothing to ask.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = defaults.data(forKey: "gauge.layout")
            .flatMap { try? JSONDecoder().decode(GaugeLayout.self, from: $0) } ?? .standard
    }
}
