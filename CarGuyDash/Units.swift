import Foundation
import Observation

nonisolated enum TemperatureUnit: String, CaseIterable {
    case celsius = "°C"
    case fahrenheit = "°F"
}

nonisolated enum PressureUnit: String, CaseIterable {
    case bar, psi, kPa
}

nonisolated enum SpeedUnit: String, CaseIterable {
    case kmh = "km/h"
    case mph
}

/// The three unit choices. Values are always stored in °C, kPa and km/h; only the text on screen is converted.
nonisolated struct Units: Equatable {
    var temperature = TemperatureUnit.celsius
    var pressure = PressureUnit.bar
    var speed = SpeedUnit.kmh
}

/// The units the user picked, saved on the iPhone (UserDefaults).
@Observable final class UnitSettings {
    var units: Units {
        didSet {
            defaults.set(units.temperature.rawValue, forKey: "unit.temperature")
            defaults.set(units.pressure.rawValue, forKey: "unit.pressure")
            defaults.set(units.speed.rawValue, forKey: "unit.speed")
        }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        units = Units(
            temperature: defaults.string(forKey: "unit.temperature").flatMap(TemperatureUnit.init) ?? .celsius,
            pressure: defaults.string(forKey: "unit.pressure").flatMap(PressureUnit.init) ?? .bar,
            speed: defaults.string(forKey: "unit.speed").flatMap(SpeedUnit.init) ?? .kmh
        )
    }
}

extension Sensor {
    /// The unit shown on screen: the sensor's own unit (°C, kPa, km/h) swapped for the chosen one.
    func displayUnit(_ units: Units) -> String {
        switch unit {
        case "°C": units.temperature.rawValue
        case "kPa": units.pressure.rawValue
        case "km/h": units.speed.rawValue
        default: unit
        }
    }

    /// The decoded value (in °C, kPa or km/h) converted to the chosen unit.
    func displayValue(_ value: Double, _ units: Units) -> Double {
        switch unit {
        case "°C": units.temperature == .fahrenheit ? value * 9 / 5 + 32 : value
        case "kPa":
            switch units.pressure {
            case .bar: value / 100
            case .psi: value * 0.145038
            case .kPa: value
            }
        case "km/h": units.speed == .mph ? value * 0.621371 : value
        default: value
        }
    }
}
