import Foundation

/// A car the app knows: VIN + make + model. Sensors are not part of it: they are rediscovered on every connection.
struct CarProfile: Codable, Equatable {
    let vin: String
    var make: String
    var model: String

    /// "Make Model", as shown on the Dashboard.
    var name: String { "\(make) \(model)" }
}

/// The saved cars, kept only on this iPhone (UserDefaults), one per VIN.
final class CarProfiles {
    private let defaults: UserDefaults
    private let key = "carProfiles"

    /// Tests pass their own `UserDefaults(suiteName:)`, so they never touch the real saved cars.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func profile(for vin: String) -> CarProfile? {
        all[vin]
    }

    func save(_ profile: CarProfile) {
        var profiles = all
        profiles[profile.vin] = profile
        defaults.set(try? JSONEncoder().encode(profiles), forKey: key)
    }

    private var all: [String: CarProfile] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: CarProfile].self, from: $0) } ?? [:]
    }
}
