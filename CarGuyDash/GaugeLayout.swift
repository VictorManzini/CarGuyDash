import Foundation

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

    /// Display only, for the pickers and lists: the favorites first, in this order, then every other source by name (case-insensitive).
    /// `all` and `Sensor.allCases` keep their order: other code depends on it.
    static let menuOrder: [GaugeSource] = {
        let favorites: [GaugeSource] = [.sensor(.rpm), .sensor(.coolantTemp), .sensor(.oilTemp), .sensor(.speed), .boost, .sensor(.moduleVoltage)]
        let rest = all.filter { !favorites.contains($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return favorites + rest
    }()

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

/// How a gauge is drawn on top of its style: A = factory instrument cluster, B = race dash, C = aftermarket pod gauge.
/// Saved as "A", "B", "C".
nonisolated enum GaugeFinish: String, Codable, CaseIterable {
    case oem = "A", race = "B", aftermarket = "C"

    var title: String {
        switch self {
        case .oem: "A · OEM"
        case .race: "B · Race"
        case .aftermarket: "C · Aftermarket"
        }
    }
}

nonisolated struct GaugeSlot: Codable, Equatable {
    var source: GaugeSource
    var style: GaugeStyle
    var look: GaugeFinish = .oem
}

nonisolated extension GaugeSlot {
    private enum CodingKeys: String, CodingKey { case source, style, look }

    /// Layouts saved before the looks existed have no `look`: they open as A.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(GaugeSource.self, forKey: .source)
        style = try container.decode(GaugeStyle.self, forKey: .style)
        look = try container.decodeIfPresent(GaugeFinish.self, forKey: .look) ?? .oem
    }
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

    /// Hides one visible gauge; the ones after it move up one place. It becomes the first hidden slot,
    /// so all six slots stay and adding a gauge right after brings it back. The last gauge cannot be removed.
    mutating func remove(at index: Int) {
        guard count > 1, slots.indices.contains(index), index < count else { return }
        slots.insert(slots.remove(at: index), at: count - 1)
        count -= 1
    }

    /// Rows and columns of the gauges page. Portrait: 1 = full screen, 2 = two rows, 3–4 = 2×2, 5–6 = two columns of three.
    /// Landscape swaps rows and columns.
    static func grid(for count: Int, wide: Bool) -> (columns: Int, rows: Int) {
        let portrait = switch count {
        case ...1: (columns: 1, rows: 1)
        case 2: (columns: 1, rows: 2)
        case 3...4: (columns: 2, rows: 2)
        default: (columns: 2, rows: 3)
        }
        return wide ? (portrait.rows, portrait.columns) : portrait
    }

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
