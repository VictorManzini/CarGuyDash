import Foundation
import Observation

/// A car the app knows: make, model, its own gauge layout and its own ranges.
/// `vin` nil = created by hand in Settings → Cars and not linked to a car yet; the first connection with a new VIN can link it.
/// Sensors are not part of it: they are rediscovered on every connection. Units are not either: they are the owner's, not the car's.
nonisolated struct CarProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var vin: String?
    var make: String
    var model: String
    var layout: GaugeLayout
    /// Only the ranges the user changed; key = the source's raw value (sensor PID, or "boost"). Any other one uses `standard(for:)`.
    var ranges: [String: GaugeRange]

    /// A new car starts with the app's default layout and ranges.
    init(id: UUID = UUID(), vin: String? = nil, make: String, model: String,
         layout: GaugeLayout = .standard, ranges: [String: GaugeRange] = [:]) {
        self.id = id
        self.vin = vin
        self.make = make
        self.model = model
        self.layout = layout
        self.ranges = ranges
    }

    /// "Make Model", as shown on the Dashboard.
    var name: String { "\(make) \(model)" }

    /// What the screen shows instead of the VIN: only its last 4 characters. The full VIN is never shown.
    var vinLabel: String { vin.map { "VIN •••• \($0.suffix(4))" } ?? "Not linked yet" }

    func range(for source: GaugeSource) -> GaugeRange {
        ranges[source.rawValue] ?? .standard(for: source)
    }

    /// Saves a range typed in the chosen units, converted to the internal unit.
    /// Returns why it was not saved (see `GaugeRange.problem`), or nil when it was.
    mutating func saveRange(typed: GaugeRange, for source: GaugeSource, units: Units) -> String? {
        if let problem = typed.problem { return problem }
        ranges[source.rawValue] = typed.convertedBack(for: source.sensor, units)
        return nil
    }

    /// Back to `standard(for:)`.
    mutating func resetRange(_ source: GaugeSource) {
        ranges[source.rawValue] = nil
    }
}

/// The saved cars, kept only on this iPhone (UserDefaults, as JSON), and which one was used last.
@Observable final class CarProfiles {
    private(set) var all: [CarProfile] {
        didSet {
            defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
            onChange?()
        }
    }
    /// The car picked by "Use this car" or matched by VIN on the last connection.
    private(set) var lastUsedID: UUID? {
        didSet {
            defaults.set(lastUsedID?.uuidString, forKey: Self.lastUsedKey)
            onChange?()
        }
    }
    /// Called after every change; the scanner uses it to wake a polling loop that had nothing to ask.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private static let key = "carProfiles.v2"
    private static let lastUsedKey = "carProfiles.lastUsed"
    /// Before per-car layouts: one profile per VIN (VIN + make + model) and one global layout and ranges.
    /// Read once to migrate, never written or deleted.
    private static let oldKey = "carProfiles", oldLayoutKey = "gauge.layout", oldRangesKey = "gauge.ranges"

    /// Tests pass their own `UserDefaults(suiteName:)`, so they never touch the real saved cars.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastUsedID = defaults.string(forKey: Self.lastUsedKey).flatMap(UUID.init)
        if let data = defaults.data(forKey: Self.key) {
            all = (try? JSONDecoder().decode([CarProfile].self, from: data)) ?? []
        } else {
            all = Self.migrated(from: defaults)
            defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
        }
    }

    /// Each car saved the old way becomes a new profile with a copy of the old global layout and ranges.
    private static func migrated(from defaults: UserDefaults) -> [CarProfile] {
        struct OldProfile: Decodable { let vin: String, make: String, model: String }
        let decoder = JSONDecoder()
        let old = defaults.data(forKey: oldKey).flatMap { try? decoder.decode([String: OldProfile].self, from: $0) } ?? [:]
        let layout = defaults.data(forKey: oldLayoutKey).flatMap { try? decoder.decode(GaugeLayout.self, from: $0) } ?? .standard
        let ranges = defaults.data(forKey: oldRangesKey).flatMap { try? decoder.decode([String: GaugeRange].self, from: $0) } ?? [:]
        return old.values
            .map { CarProfile(vin: $0.vin, make: $0.make, model: $0.model, layout: layout, ranges: ranges) }
            .sorted { $0.name < $1.name }
    }

    /// The car whose layout and ranges are in use: the last one used, or the first one if that is gone.
    /// On a connection the scanner marks the car matched by VIN as used, so connected = that car.
    var active: CarProfile? { all.first { $0.id == lastUsedID } ?? all.first }

    func profile(for vin: String) -> CarProfile? {
        all.first { $0.vin == vin }
    }

    func profile(id: UUID) -> CarProfile? {
        all.first { $0.id == id }
    }

    /// Adds a car with the default layout and ranges. Blank make or model: nothing is added.
    @discardableResult
    func add(make: String, model: String, vin: String? = nil) -> CarProfile? {
        let make = make.trimmingCharacters(in: .whitespaces), model = model.trimmingCharacters(in: .whitespaces)
        guard !make.isEmpty, !model.isEmpty else { return nil }
        let profile = CarProfile(vin: vin, make: make, model: model)
        all.append(profile)
        return profile
    }

    /// Changes one saved car in place (nothing happens if it was deleted).
    func update(_ id: UUID, _ change: (inout CarProfile) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
    }

    /// Makes this car the active one.
    func use(_ id: UUID) {
        guard lastUsedID != id else { return }
        lastUsedID = id
    }
}
