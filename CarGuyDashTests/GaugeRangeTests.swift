import Foundation
import Testing
@testable import CarGuyDash

struct GaugeRangeTests {
    /// The coolant band saved before targets (five values).
    private let oldCoolant = GaugeRange(min: 40, max: 130, rpm: RPMZones(normalLow: 90, normalHigh: 105, redline: 115))

    @Test func coolantColorsFollowTheTarget() {
        let range = GaugeRange.standard(for: .coolantTemp) // 40 / 95 / 115
        #expect(range.color(at: 30) == .blue)  // below the scale
        #expect(range.color(at: 60) == .blue)
        #expect(range.color(at: 94.9) == .blue)
        #expect(range.color(at: 95) == .green) // target
        #expect(range.color(at: 104.9) == .green)
        #expect(range.color(at: 105) == .yellow) // halfway from the target to max
        #expect(range.color(at: 110) == .orange) // three quarters of the way
        #expect(range.color(at: 114.9) == .orange)
        #expect(range.color(at: 115) == .red)    // max
        #expect(range.color(at: 130) == .red)
    }

    @Test func theGradientIsPureGreenAtTheTargetAndPureRedAtMax() {
        let range = GaugeRange(min: 0, max: 100, target: 60) // yellow at 80, orange at 90
        #expect(range.rgb(at: 0) == GaugeColor.blue.rgb)
        #expect(range.rgb(at: 60) == GaugeColor.green.rgb)
        #expect(range.rgb(at: 80) == GaugeColor.yellow.rgb)
        #expect(range.rgb(at: 90) == GaugeColor.orange.rgb)
        #expect(range.rgb(at: 100) == GaugeColor.red.rgb)
        #expect(range.rgb(at: 99.9) != GaugeColor.red.rgb)
        // Smooth between them: halfway from blue to green.
        let blue = GaugeColor.blue.rgb, green = GaugeColor.green.rgb, middle = range.rgb(at: 30)
        #expect(abs(middle.r - (blue.r + green.r) / 2) < 1e-9 && abs(middle.g - (blue.g + green.g) / 2) < 1e-9)
        // A target at the min: no blue.
        #expect(GaugeRange(min: 0, max: 100, target: 0).stops.first?.color == .green)
    }

    @Test func noTargetIsAllGreen() {
        let oil = GaugeRange.standard(for: .oilTemp)
        #expect(oil.target == nil)
        #expect(oil.stops.map(\.color) == [.green])
        for value in [-50.0, -40, 100, 214, 215, 300] {
            #expect(oil.color(at: value) == .green)
            #expect(oil.rgb(at: value) == GaugeColor.green.rgb)
        }
    }

    @Test func rpmColorsStartGreen() {
        let range = GaugeRange.standard(for: .rpm)
        #expect(range.stops.first?.color == .green) // no blue: normalLow = min
        #expect(range.color(at: 0) == .green)
        #expect(range.color(at: 3000) == .green)
        #expect(range.color(at: 6000) == .yellow)
        #expect(range.color(at: 6250) == .orange)
        #expect(range.color(at: 6499) == .orange)
        #expect(range.color(at: 6500) == .red)
        #expect(range.color(at: 7000) == .red)
    }

    @Test func theGradientMixesSmoothlyBetweenStops() {
        let range = GaugeRange.standard(for: .coolantTemp)
        let yellow = GaugeColor.yellow.rgb, orange = GaugeColor.orange.rgb
        #expect(range.rgb(at: 105) == yellow)
        #expect(range.rgb(at: 110) == orange)
        let halfway = range.rgb(at: 107.5) // halfway between yellow and orange
        let middleGreen: Double = (yellow.g + orange.g) / 2
        #expect(halfway.r == 255)
        #expect(abs(halfway.g - middleGreen) < 0.001)
        #expect(halfway.b == 0)
        #expect(range.rgb(at: 130) == GaugeColor.red.rgb)
    }

    @Test func otherSensorsUseTheFormulaRange() {
        #expect(GaugeRange.standard(for: .oilTemp) == GaugeRange(min: -40, max: 215))
        #expect(GaugeRange.standard(for: .throttlePosition) == GaugeRange(min: 0, max: 100))
        #expect(GaugeRange.standard(for: .coolantTemp) == GaugeRange(min: 40, max: 115, target: 95))
        #expect(GaugeRange.standard(for: .rpm) == GaugeRange(min: 0, max: 7000, rpm: RPMZones(normalLow: 0, normalHigh: 6000, redline: 6500)))
        let speed = GaugeRange.standard(for: .speed)
        #expect(speed.color(at: 0) == .green)
        #expect(speed.color(at: 200) == .green)
        #expect(speed.color(at: 255) == .green) // no target: green up to max
    }

    @Test func digitalIsRedOnlyFromTheRedline() {
        func reading(_ sensor: Sensor, _ value: Double, text: String? = nil) -> GaugeReading {
            GaugeReading(sensor: sensor, text: text ?? sensor.text(for: value), value: value,
                         range: .standard(for: sensor), units: Units())
        }
        // Above the target is fine: red only at max.
        #expect(!reading(.coolantTemp, 100).isRedline)
        #expect(!reading(.coolantTemp, 114.9).isRedline)
        #expect(reading(.coolantTemp, 115).isRedline)
        #expect(!reading(.oilTemp, 214).isRedline)
        #expect(reading(.oilTemp, 215).isRedline)
        #expect(!reading(.rpm, 6499).isRedline)
        #expect(reading(.rpm, 6500).isRedline)
        // Stand By / N/A with an old value left over: no number, never red.
        #expect(!reading(.rpm, 7000, text: "Stand By").isRedline)
        #expect(!reading(.rpm, 7000, text: "N/A").isRedline)
    }

    @Test func rangesConvertOnlyOnScreen() {
        let coolant = GaugeRange.standard(for: .coolantTemp).converted(for: .coolantTemp, Units(temperature: .fahrenheit))
        #expect(coolant == GaugeRange(min: 104, max: 239, target: 203))
        let map = GaugeRange.standard(for: .manifoldPressure).converted(for: .manifoldPressure, Units(pressure: .bar))
        #expect(map.min == 0 && map.max == 2.55)
        let speed = GaugeRange.standard(for: .speed).converted(for: .speed, Units(speed: .mph))
        #expect(abs(speed.max - 158.45) < 0.01)
        let rpm = GaugeRange.standard(for: .rpm)
        #expect(rpm.converted(for: .rpm, Units(temperature: .fahrenheit, pressure: .psi, speed: .mph)) == rpm)
    }

    @MainActor @Test func aChangedRangeIsSavedAndLoadedAgain() throws {
        let suite = "GaugeRangeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let car = try #require(CarProfiles(defaults: defaults).add(make: "BMW", model: "M135i"))
        #expect(car.range(for: .sensor(.rpm)) == .standard(for: .rpm))
        let custom = GaugeRange(min: 0, max: 8000, rpm: RPMZones(normalLow: 0, normalHigh: 6500, redline: 7000))
        CarProfiles(defaults: defaults).update(car.id) { $0.ranges["0C"] = custom }
        // A new object reading the same storage = the app opened again.
        let reopened = try #require(CarProfiles(defaults: defaults).profile(id: car.id))
        #expect(reopened.range(for: .sensor(.rpm)) == custom)
        #expect(reopened.range(for: .sensor(.coolantTemp)) == .standard(for: .coolantTemp))
    }

    @Test func validationAllowsOnlyAnOrderedRange() {
        let ok = GaugeRange(min: 0, max: 100, rpm: RPMZones(normalLow: 20, normalHigh: 60, redline: 80))
        #expect(ok.problem == nil)
        // Equal neighbours are fine: every default is valid.
        for source in GaugeSource.all { #expect(GaugeRange.standard(for: source).problem == nil, "\(source)") }
        var bad = ok; bad.max = 0
        #expect(bad.problem == "Min must be below max.")
        bad = ok; bad.rpm?.normalLow = -1
        #expect(bad.problem == "Normal low can't be below min.")
        bad = ok; bad.rpm?.normalHigh = 10
        #expect(bad.problem == "Normal high can't be below normal low.")
        bad = ok; bad.rpm?.redline = 50
        #expect(bad.problem == "Redline can't be below normal high.")
        bad = ok; bad.rpm?.redline = 101
        #expect(bad.problem == "Redline can't be above max.")

        // A target sits between min and max (both ends allowed); none at all is fine.
        let target = GaugeRange(min: 40, max: 115, target: 95)
        #expect(target.problem == nil)
        #expect(GaugeRange(min: 40, max: 115, target: 40).problem == nil)
        #expect(GaugeRange(min: 40, max: 115, target: 115).problem == nil)
        #expect(GaugeRange(min: 40, max: 115).problem == nil)
        var wrong = target; wrong.target = 39
        #expect(wrong.problem == "Target can't be below min.")
        wrong.target = 116
        #expect(wrong.problem == "Target can't be above max.")
        wrong = target; wrong.max = 40
        #expect(wrong.problem == "Min must be below max.")
    }

    @Test func oldRangesAreFittedToTheirSource() {
        // RPM keeps its five values as they were.
        let oldRPM = GaugeRange(min: 0, max: 8000, rpm: RPMZones(normalLow: 0, normalHigh: 6500, redline: 7000))
        #expect(oldRPM.fitted(to: .sensor(.rpm)) == oldRPM)
        // Another source: max = the old redline, target = the middle of the old normal band.
        #expect(oldCoolant.fitted(to: .sensor(.coolantTemp)) == GaugeRange(min: 40, max: 115, target: 97.5))
        let oldBoost = GaugeRange(min: -100, max: 150, rpm: RPMZones(normalLow: -100, normalHigh: 100, redline: 125))
        #expect(oldBoost.fitted(to: .boost) == GaugeRange(min: -100, max: 125, target: 0))
        // The old band was the whole scale (all green): no target.
        let oldOil = GaugeRange(min: -40, max: 215, rpm: RPMZones(normalLow: -40, normalHigh: 215, redline: 215))
        #expect(oldOil.fitted(to: .sensor(.oilTemp)) == GaugeRange(min: -40, max: 215))
        // A redline at the min would leave no scale: the old max stays.
        let flat = GaugeRange(min: 0, max: 100, rpm: RPMZones(normalLow: 0, normalHigh: 0, redline: 0))
        #expect(flat.fitted(to: .sensor(.speed)) == GaugeRange(min: 0, max: 100, target: 0))
        // Each source keeps only its own kind: no target on RPM (default zones if missing), no zones elsewhere.
        #expect(GaugeRange(min: 0, max: 8000, target: 3000).fitted(to: .sensor(.rpm))
                == GaugeRange(min: 0, max: 8000, rpm: GaugeRange.standard(for: .rpm).rpm))
        #expect(GaugeRange(min: 40, max: 115, target: 95).fitted(to: .sensor(.coolantTemp)) == GaugeRange(min: 40, max: 115, target: 95))
    }

    @Test func rangesAreSavedInTheNewFormatAndOldOnesStillLoad() throws {
        let new = [GaugeRange(min: 40, max: 115, target: 95), GaugeRange(min: -40, max: 215),
                   GaugeRange(min: 0, max: 7000, rpm: RPMZones(normalLow: 0, normalHigh: 6000, redline: 6500))]
        let data = try JSONEncoder().encode(new)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]]).map { Set($0.keys) }
        #expect(keys == [["min", "max", "target"], ["min", "max"], ["min", "max", "rpm"]])
        #expect(try JSONDecoder().decode([GaugeRange].self, from: data) == new)
        // Five flat values, as saved before targets: they load as zones, ready for `fitted(to:)`.
        let old = #"{"min":40,"max":130,"normalLow":90,"normalHigh":105,"redline":115}"#
        #expect(try JSONDecoder().decode(GaugeRange.self, from: Data(old.utf8)) == oldCoolant)
    }

    @Test func aTypedRangeIsSavedInTheInternalUnitOnlyWhenValid() {
        var car = CarProfile(make: "BMW", model: "M135i")

        // Coolant typed in °F comes back in °C.
        let fahrenheit = Units(temperature: .fahrenheit)
        let typed = GaugeRange(min: 104, max: 248, target: 203)
        #expect(car.saveRange(typed: typed, for: .sensor(.coolantTemp), units: fahrenheit) == nil)
        let saved = car.range(for: .sensor(.coolantTemp))
        #expect(abs(saved.min - 40) < 1e-9 && abs(saved.max - 120) < 1e-9 && abs((saved.target ?? 0) - 95) < 1e-9)
        #expect(saved.rpm == nil)

        // Boost typed in bar comes back in kPa; no target = all green.
        let boost = GaugeRange(min: -1, max: 1.5)
        #expect(car.saveRange(typed: boost, for: .boost, units: Units(pressure: .bar)) == nil)
        #expect(car.range(for: .boost) == GaugeRange(min: -100, max: 150))

        // An invalid one is not saved: the old one stays.
        var wrong = boost; wrong.target = 2
        #expect(car.saveRange(typed: wrong, for: .boost, units: Units(pressure: .bar)) == "Target can't be above max.")
        #expect(car.range(for: .boost) == GaugeRange(min: -100, max: 150))

        // Reset brings the default back.
        car.resetRange(.boost)
        #expect(car.range(for: .boost) == .standard(for: .boost))
        #expect(GaugeRange.standard(for: .boost) == GaugeRange(min: -101, max: 154))
    }

    @Test func dialNumbersSitOnRoundMajorTicks() {
        func majors(_ scale: DialScale) -> [String] { scale.ticks.filter(\.isMajor).map { scale.label($0.value) } }
        // RPM in thousands, step 1000.
        let rpm = DialScale(min: 0, max: 7000)
        #expect(rpm.step == 1000 && majors(rpm) == ["0", "1", "2", "3", "4", "5", "6", "7"])
        // Oil −40…215 °C: step 50, numbers on its multiples only.
        let oil = DialScale(min: -40, max: 215)
        #expect(oil.step == 50 && majors(oil) == ["0", "50", "100", "150", "200"])
        // Boost in bar −1.01…1.54: step 0.5, no float drift ("-0.5", not "-0.49999").
        let boost = DialScale(min: -1.01, max: 1.54)
        #expect(majors(boost) == ["-1", "-0.5", "0", "0.5", "1", "1.5"])
        // Coolant 40…130 °C: step 20 (a 2), so four minor gaps per number.
        let coolant = DialScale(min: 40, max: 130)
        #expect(majors(coolant) == ["40", "60", "80", "100", "120"])
        #expect(coolant.ticks.count == 19) // 40, 45, … 130
        // Every step is 1, 2 or 5 × 10ⁿ, and at most 8 gaps between numbers.
        for (low, high) in [(0.0, 65.535), (-40, 215), (104, 266), (0, 2.55), (0, 255), (-14.6, 22.3)] {
            let scale = DialScale(min: low, max: high)
            let mantissa = scale.step / pow(10, floor(log10(scale.step)))
            #expect([1, 2, 5].contains { abs($0 - mantissa) < 1e-9 }, "\(low)…\(high)")
            #expect((high - low) / scale.step <= 8 + 1e-9)
        }
    }
}
