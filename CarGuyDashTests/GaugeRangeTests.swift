import Foundation
import Testing
@testable import CarGuyDash

struct GaugeRangeTests {
    @Test func coolantColors() {
        let range = GaugeRange.standard(for: .coolantTemp)
        #expect(range.color(at: 30) == .blue)  // below the scale
        #expect(range.color(at: 60) == .blue)  // below normalLow (90)
        #expect(range.color(at: 90) == .green)
        #expect(range.color(at: 95) == .green)
        #expect(range.color(at: 104.9) == .green)
        #expect(range.color(at: 105) == .red)  // normalHigh = redline: red wins
        #expect(range.color(at: 115) == .red)
    }

    @Test func rpmColorsStartGreen() {
        let range = GaugeRange.standard(for: .rpm)
        #expect(range.stops.first?.color == .green) // no blue: normalLow = min
        #expect(range.color(at: 0) == .green)
        #expect(range.color(at: 3000) == .green)
        #expect(range.color(at: 6000) == .yellow)
        #expect(range.color(at: 6499) == .yellow)
        #expect(range.color(at: 6500) == .red)
        #expect(range.color(at: 7000) == .red)
    }

    @Test func otherSensorsUseTheFormulaRange() {
        #expect(GaugeRange.standard(for: .oilTemp) == GaugeRange(min: -40, max: 215, normalLow: -40, normalHigh: 215, redline: 215))
        #expect(GaugeRange.standard(for: .throttlePosition) == GaugeRange(min: 0, max: 100, normalLow: 0, normalHigh: 100, redline: 100))
        let speed = GaugeRange.standard(for: .speed)
        #expect(speed.color(at: 0) == .green)
        #expect(speed.color(at: 200) == .green)
        #expect(speed.color(at: 255) == .red) // redline = max
    }

    @Test func digitalIsRedOnlyFromTheRedline() {
        func reading(_ sensor: Sensor, _ value: Double, text: String? = nil) -> GaugeReading {
            GaugeReading(sensor: sensor, text: text ?? sensor.text(for: value), value: value,
                         range: .standard(for: sensor), units: Units())
        }
        #expect(!reading(.coolantTemp, 104.9).isRedline)
        #expect(reading(.coolantTemp, 105).isRedline)
        #expect(!reading(.rpm, 6499).isRedline)
        #expect(reading(.rpm, 6500).isRedline)
        // Stand By / N/A with an old value left over: no number, never red.
        #expect(!reading(.rpm, 7000, text: "Stand By").isRedline)
        #expect(!reading(.rpm, 7000, text: "N/A").isRedline)
    }

    @Test func rangesConvertOnlyOnScreen() {
        let coolant = GaugeRange.standard(for: .coolantTemp).converted(for: .coolantTemp, Units(temperature: .fahrenheit))
        #expect(coolant == GaugeRange(min: 104, max: 266, normalLow: 194, normalHigh: 221, redline: 221))
        let map = GaugeRange.standard(for: .manifoldPressure).converted(for: .manifoldPressure, Units(pressure: .bar))
        #expect(map.min == 0 && map.max == 2.55)
        let speed = GaugeRange.standard(for: .speed).converted(for: .speed, Units(speed: .mph))
        #expect(abs(speed.max - 158.45) < 0.01)
        let rpm = GaugeRange.standard(for: .rpm)
        #expect(rpm.converted(for: .rpm, Units(temperature: .fahrenheit, pressure: .psi, speed: .mph)) == rpm)
    }

    @Test func aChangedRangeIsSavedAndLoadedAgain() throws {
        let suite = "GaugeRangeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(GaugeRangeSettings(defaults: defaults).range(for: .rpm) == .standard(for: .rpm))
        let custom = GaugeRange(min: 0, max: 8000, normalLow: 0, normalHigh: 6500, redline: 7000)
        GaugeRangeSettings(defaults: defaults).set(custom, for: .rpm)
        // A new object reading the same storage = the app opened again.
        let reopened = GaugeRangeSettings(defaults: defaults)
        #expect(reopened.range(for: .rpm) == custom)
        #expect(reopened.range(for: .coolantTemp) == .standard(for: .coolantTemp))
    }
}
