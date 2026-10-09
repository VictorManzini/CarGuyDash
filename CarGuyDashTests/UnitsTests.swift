import Foundation
import Testing
@testable import CarGuyDash

struct UnitsTests {
    private func text(_ sensor: Sensor, _ value: Double, _ units: Units) -> String {
        "\(sensor.text(for: value, units: units)) \(sensor.displayUnit(units))"
    }

    @Test func defaultsAreCelsiusBarKmh() {
        let units = Units()
        #expect(text(.oilTemp, 96, units) == "96 °C")
        #expect(text(.manifoldPressure, 93, units) == "0.93 bar")
        #expect(text(.speed, 100, units) == "100 km/h")
    }

    @Test func knownConversions() {
        #expect(text(.oilTemp, 96, Units(temperature: .fahrenheit)) == "205 °F")
        #expect(text(.coolantTemp, 0, Units(temperature: .fahrenheit)) == "32 °F")
        #expect(text(.manifoldPressure, 93, Units(pressure: .psi)) == "13.5 psi")
        #expect(text(.manifoldPressure, 93, Units(pressure: .kPa)) == "93 kPa")
        #expect(text(.fuelRailPressure, 20000, Units()) == "200.00 bar")
        #expect(text(.speed, 100, Units(speed: .mph)) == "62 mph")
    }

    @Test func otherSensorsDoNotChange() {
        let units = Units(temperature: .fahrenheit, pressure: .psi, speed: .mph)
        #expect(text(.rpm, 750, units) == "750 rpm")
        #expect(text(.moduleVoltage, 13.7, units) == "13.7 V")
        #expect(text(.throttlePosition, 15, units) == "15 %")
    }

    @Test func naAndStandByDoNotChange() {
        let units = Units(temperature: .fahrenheit, pressure: .psi, speed: .mph)
        #expect(gaugeText(for: .oilTemp, state: .ready, value: nil, units: units) == "N/A")
        #expect(gaugeText(for: .oilTemp, state: .disconnected, value: 96, units: units) == "N/A")
        #expect(gaugeText(for: .oilTemp, state: .reconnecting, value: 96, units: units) == "Stand By")
        #expect(gaugeText(for: .oilTemp, state: .ready, value: 96, silent: true, units: units) == "Stand By")
        #expect(gaugeText(for: .oilTemp, state: .ready, value: 96, units: units) == "205")
    }

    @Test func theChoiceIsSavedAndLoadedAgain() throws {
        let suite = "UnitsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UnitSettings(defaults: defaults).units == Units()) // nothing saved yet
        let first = UnitSettings(defaults: defaults)
        first.units = Units(temperature: .fahrenheit, pressure: .psi, speed: .mph)
        // A new object reading the same storage = the app opened again.
        #expect(UnitSettings(defaults: defaults).units == Units(temperature: .fahrenheit, pressure: .psi, speed: .mph))
    }
}
