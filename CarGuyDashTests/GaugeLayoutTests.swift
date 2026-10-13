import Foundation
import Testing
@testable import CarGuyDash

struct GaugeLayoutTests {
    @Test func theCountIsLockedBetweenOneAndSix() {
        var layout = GaugeLayout.standard
        #expect(layout.count == 6)
        layout.count = 0
        #expect(layout.count == 1)
        layout.count = 7
        #expect(layout.count == 6)
        layout.count = 3
        #expect(layout.visibleSlots.count == 3)
        #expect(layout.slots.count == 6) // the hidden slots are kept
        #expect(GaugeLayout(slots: GaugeLayout.standard.slots, count: 99).count == 6)
    }

    @Test func menuOrderHasTheFavoritesFirstThenTheRestByName() {
        let order = GaugeSource.menuOrder
        let favorites: [GaugeSource] = [.sensor(.rpm), .sensor(.coolantTemp), .sensor(.oilTemp), .sensor(.speed), .boost, .sensor(.moduleVoltage)]
        #expect(Array(order.prefix(6)) == favorites)
        #expect(order.count == GaugeSource.all.count)
        #expect(Set(order) == Set(GaugeSource.all)) // every source, exactly once (count and set size match)
        let rest = order.dropFirst(6).map(\.name)
        #expect(rest == rest.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test func removingAGaugeKeepsTheOrderAndAllSixSlots() {
        var layout = GaugeLayout.standard
        layout.count = 4 // RPM, coolant, oil, Boost visible
        layout.remove(at: 1)
        #expect(layout.count == 3)
        #expect(layout.visibleSlots.map(\.source) == [.sensor(.rpm), .sensor(.oilTemp), .boost])
        #expect(layout.slots.count == 6)
        layout.count += 1 // adding brings the removed one back at the end
        #expect(layout.visibleSlots.last?.source == .sensor(.coolantTemp))

        layout.count = 1
        layout.remove(at: 0) // the last gauge stays
        #expect(layout.count == 1)
        layout.remove(at: 5) // a hidden slot is not removed
        #expect(layout.count == 1)
    }

    @Test func pollingAsksTheVisibleSensorsTheCarSupports() {
        var layout = GaugeLayout.standard
        // Default: RPM, coolant, oil, Boost (0B), intake air, module voltage.
        #expect(layout.sensorsToPoll(supported: nil) == [.rpm, .coolantTemp, .oilTemp, .manifoldPressure, .intakeAirTemp, .moduleVoltage])
        // The car lacks oil (5C) and voltage (42).
        #expect(layout.sensorsToPoll(supported: [0x0C, 0x05, 0x0B, 0x0F]) == [.rpm, .coolantTemp, .manifoldPressure, .intakeAirTemp])
        // Only the visible slots count.
        layout.count = 2
        #expect(layout.sensorsToPoll(supported: nil) == [.rpm, .coolantTemp])
        #expect(layout.sensorsToPoll(supported: []) == [])
    }

    @Test func boostAsksTheManifoldPressureOnce() {
        let layout = GaugeLayout(slots: [
            GaugeSlot(source: .boost, style: .arc),
            GaugeSlot(source: .sensor(.manifoldPressure), style: .digital),
            GaugeSlot(source: .boost, style: .bar),
        ], count: 3)
        #expect(layout.sensorsToPoll(supported: nil) == [.manifoldPressure])
        #expect(GaugeSource.boost.sensor == .manifoldPressure)
        #expect(GaugeSource.all.count == Sensor.allCases.count + 1)
    }

    @Test func anOldLayoutWithoutALookOpensAsA() throws {
        let old = #"{"slots":[{"source":"0C","style":"Analog"},{"source":"boost","style":"Bar"}],"count":2}"#
        let layout = try JSONDecoder().decode(GaugeLayout.self, from: Data(old.utf8))
        #expect(layout.count == 2)
        #expect(layout.slots == [GaugeSlot(source: .sensor(.rpm), style: .analog, look: .oem),
                                 GaugeSlot(source: .boost, style: .bar, look: .oem)])
        // A saved look comes back.
        let saved = try JSONEncoder().encode(GaugeSlot(source: .sensor(.oilTemp), style: .arc, look: .race))
        #expect(try JSONDecoder().decode(GaugeSlot.self, from: saved).look == .race)
    }

    @MainActor @Test func aCarsLayoutIsSavedAndLoadedAgain() throws {
        let suite = "GaugeLayoutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let profiles = CarProfiles(defaults: defaults)
        let car = try #require(profiles.add(make: "BMW", model: "M135i"))
        #expect(car.layout == .standard) // a new car starts with the default layout
        profiles.update(car.id) {
            $0.layout.count = 4
            $0.layout.slots[1] = GaugeSlot(source: .sensor(.speed), style: .digital)
            $0.layout.slots[3] = GaugeSlot(source: .boost, style: .bar)
        }
        // A new object reading the same storage = the app opened again.
        let reopened = try #require(CarProfiles(defaults: defaults).profile(id: car.id)?.layout)
        #expect(reopened.count == 4)
        #expect(reopened.slots[1] == GaugeSlot(source: .sensor(.speed), style: .digital))
        #expect(reopened.slots[3] == GaugeSlot(source: .boost, style: .bar))
        #expect(reopened == profiles.profile(id: car.id)?.layout)
    }
}
