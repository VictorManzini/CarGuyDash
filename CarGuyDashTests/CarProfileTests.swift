import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct CarProfileTests {
    /// A scanner on the simulated adapter (fake VIN) with its own throwaway saved cars.
    private func scanner(suite: String = UUID().uuidString) async -> BluetoothScanner {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let scanner = BluetoothScanner(defaults: defaults)
        await scanner.useSimulatedAdapter()
        return scanner
    }

    private func waitReady(_ scanner: BluetoothScanner) async throws {
        let start = ContinuousClock.now
        while !scanner.isReady && ContinuousClock.now - start < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func newVINAsksForMakeAndModel() async {
        let scanner = await scanner()
        #expect(scanner.isReady)
        #expect(scanner.vin == SimulatedAdapter.fakeVIN)
        #expect(scanner.needsCarInfo)
        #expect(scanner.carName == "Unknown car")

        scanner.saveCar(make: " BMW ", model: "M135i")
        #expect(!scanner.needsCarInfo)
        #expect(scanner.carName == "BMW M135i")
    }

    @Test func blankMakeOrModelIsNotSaved() async {
        let scanner = await scanner()
        scanner.saveCar(make: "BMW", model: "  ")
        scanner.saveCar(make: "", model: "M135i")
        #expect(scanner.needsCarInfo)
        #expect(scanner.carName == "Unknown car")
    }

    @Test func knownVINDoesNotAsk() async {
        let suite = UUID().uuidString
        let first = await scanner(suite: suite)
        first.saveCar(make: "BMW", model: "M135i")

        // A new launch of the app with the same saved cars.
        let second = BluetoothScanner(defaults: UserDefaults(suiteName: suite)!)
        await second.useSimulatedAdapter()
        #expect(!second.needsCarInfo)
        #expect(second.carName == "BMW M135i")
    }

    @Test func skippingKeepsItUnknownAndAsksAgainNextConnection() async throws {
        let scanner = await scanner()
        scanner.skipCarInfo()
        #expect(!scanner.needsCarInfo)
        #expect(scanner.carName == "Unknown car")

        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(scanner.needsCarInfo)
    }

    @Test func noVINMeansUnknownCarAndReadingContinues() async throws {
        let scanner = await scanner()
        let simulated = try #require(scanner.simulator)
        scanner.saveCar(make: "BMW", model: "M135i")
        simulated.noDataChance = 0

        // Next connection the car does not answer 0902.
        simulated.answersVIN = false
        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(scanner.vin == nil)
        #expect(scanner.carName == "Unknown car")
        #expect(!scanner.needsCarInfo) // nothing to ask without a VIN

        // Still reads normally.
        scanner.startPolling()
        let start = ContinuousClock.now
        while scanner.liveData.value(for: .oilTemp) == nil && ContinuousClock.now - start < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
        scanner.stopPolling()
        #expect(scanner.liveData.value(for: .oilTemp) == 67)
    }

    @Test func theVINRequestPassesTheGatekeeperOncePerConnection() async throws {
        let scanner = await scanner()
        let simulated = try #require(scanner.simulator)
        #expect(Gatekeeper.check("0902") == .allowed)
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 1)
        // It comes right after the setup commands, then the supported-PID blocks.
        #expect(simulated.received == (BluetoothScanner.setupCommands + ["0902", "0100", "0120", "0140", "0160"]).map { $0 + "\r" })

        // Polling does not ask again; a new connection does.
        simulated.noDataChance = 0
        scanner.startPolling()
        try await Task.sleep(for: .milliseconds(500))
        scanner.stopPolling()
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 1)
        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 2)
    }
}

/// Per-car layouts and ranges, cars created by hand, the active car, and the migration from the old storage.
@MainActor
struct CarProfilesTests {
    private func freshDefaults() -> UserDefaults {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitReady(_ scanner: BluetoothScanner) async throws {
        let start = ContinuousClock.now
        while !scanner.isReady && ContinuousClock.now - start < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(scanner.isReady)
    }

    private func layout(_ source: GaugeSource) -> GaugeLayout {
        var layout = GaugeLayout.standard
        layout.count = 1
        layout.slots[0].source = source
        return layout
    }

    @Test func oldProfilesBecomeNewOnesWithACopyOfTheGlobalLayoutAndRanges() async throws {
        let defaults = freshDefaults()
        // Saved the old way: cars by VIN, one global layout, one set of ranges.
        let old = #"{"\#(SimulatedAdapter.fakeVIN)":{"vin":"\#(SimulatedAdapter.fakeVIN)","make":"BMW","model":"M135i"}}"#
        defaults.set(Data(old.utf8), forKey: "carProfiles")
        let globalLayout = layout(.boost)
        let redline = GaugeRange(min: 0, max: 8000, rpm: RPMZones(normalLow: 0, normalHigh: 6500, redline: 7000))
        defaults.set(try JSONEncoder().encode(globalLayout), forKey: "gauge.layout")
        defaults.set(try JSONEncoder().encode(["0C": redline]), forKey: "gauge.ranges")

        let profiles = CarProfiles(defaults: defaults)
        let car = try #require(profiles.all.first)
        #expect(profiles.all.count == 1)
        #expect(car.vin == SimulatedAdapter.fakeVIN)
        #expect(car.name == "BMW M135i")
        #expect(car.layout == globalLayout)
        #expect(car.range(for: .sensor(.rpm)) == redline)
        #expect(car.range(for: .sensor(.coolantTemp)) == .standard(for: .coolantTemp))
        #expect(profiles.active == car)
        // The old keys are kept, only no longer used.
        #expect(defaults.data(forKey: "carProfiles") != nil)
        #expect(defaults.data(forKey: "gauge.layout") != nil)
        #expect(defaults.data(forKey: "gauge.ranges") != nil)

        // Migrated once: the next launch reads the new storage (same id), even if the old keys change.
        defaults.set(try JSONEncoder().encode(GaugeLayout.standard), forKey: "gauge.layout")
        #expect(CarProfiles(defaults: defaults).all == [car])

        // And the connection recognises the car by its VIN.
        let scanner = BluetoothScanner(defaults: defaults)
        await scanner.useSimulatedAdapter()
        #expect(!scanner.needsCarInfo)
        #expect(scanner.car == car)
        #expect(scanner.layout == globalLayout)
    }

    @Test func twoCarsSavedBeforeTargetsLoadWithNothingLost() throws {
        let defaults = freshDefaults()
        // Exactly as saved before targets: every range with five flat values.
        let old = #"""
        [{"id":"11111111-1111-1111-1111-111111111111","vin":"TESTVIN0000000001","make":"BMW","model":"M135i",
          "layout":{"slots":[{"source":"0C","style":"Analog","look":"B"},{"source":"05","style":"Arc","look":"C"}],"count":2},
          "ranges":{"0C":{"min":0,"max":8000,"normalLow":0,"normalHigh":6500,"redline":7000},
                    "05":{"min":40,"max":130,"normalLow":90,"normalHigh":105,"redline":115},
                    "5C":{"min":-40,"max":215,"normalLow":-40,"normalHigh":215,"redline":215},
                    "boost":{"min":-100,"max":150,"normalLow":-100,"normalHigh":100,"redline":125}}},
         {"id":"22222222-2222-2222-2222-222222222222","make":"Mazda","model":"MX-5",
          "layout":{"slots":[{"source":"0D","style":"Digital"}],"count":1},"ranges":{}}]
        """#
        defaults.set(Data(old.utf8), forKey: "carProfiles.v2")
        defaults.set("22222222-2222-2222-2222-222222222222", forKey: "carProfiles.lastUsed")

        let profiles = CarProfiles(defaults: defaults)
        #expect(profiles.loadProblem == nil)
        #expect(profiles.all.count == 2)
        let bmw = try #require(profiles.all.first), mazda = try #require(profiles.all.last)
        #expect(bmw.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(bmw.vin == "TESTVIN0000000001" && bmw.name == "BMW M135i")
        #expect(bmw.layout == GaugeLayout(slots: [GaugeSlot(source: .sensor(.rpm), style: .analog, look: .race),
                                                  GaugeSlot(source: .sensor(.coolantTemp), style: .arc, look: .aftermarket)], count: 2))
        // RPM unchanged; the others converted: max = old redline, target = middle of the old normal band, none if it was all green.
        #expect(bmw.ranges == [
            "0C": GaugeRange(min: 0, max: 8000, rpm: RPMZones(normalLow: 0, normalHigh: 6500, redline: 7000)),
            "05": GaugeRange(min: 40, max: 115, target: 97.5),
            "5C": GaugeRange(min: -40, max: 215),
            "boost": GaugeRange(min: -100, max: 125, target: 0),
        ])
        #expect(mazda.id == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(mazda.vin == nil && mazda.name == "Mazda MX-5" && mazda.ranges.isEmpty)
        #expect(mazda.layout == GaugeLayout(slots: [GaugeSlot(source: .sensor(.speed), style: .digital)], count: 1))
        #expect(profiles.active == mazda)

        // The next save writes the new format; reading it again gives the same cars.
        profiles.update(bmw.id) { $0.model = "M135i" }
        #expect(String(decoding: defaults.data(forKey: "carProfiles.v2") ?? Data(), as: UTF8.self).contains("\"target\":97.5"))
        #expect(CarProfiles(defaults: defaults).all == profiles.all)
    }

    @Test func savedCarsThatCannotBeReadAreNeverOverwritten() throws {
        let defaults = freshDefaults()
        let unreadable = Data(#"[{"id":"not a uuid","make":"BMW"}]"#.utf8)
        defaults.set(unreadable, forKey: "carProfiles.v2")

        let profiles = CarProfiles(defaults: defaults)
        #expect(profiles.all.isEmpty)
        #expect(profiles.loadProblem?.hasPrefix("Saved cars could not be read") == true)
        // Changes work for this run but never reach the storage.
        let car = try #require(profiles.add(make: "Mazda", model: "MX-5"))
        profiles.update(car.id) { $0.layout.count = 2 }
        profiles.delete(car.id)
        #expect(defaults.data(forKey: "carProfiles.v2") == unreadable)
        // The scanner writes it to the log once.
        let scanner = BluetoothScanner(defaults: defaults)
        #expect(scanner.log.filter { $0.contains("Saved cars could not be read") }.count == 1)
        #expect(defaults.data(forKey: "carProfiles.v2") == unreadable)
    }

    @Test func nothingSavedBeforeMeansNoCars() {
        #expect(CarProfiles(defaults: freshDefaults()).all.isEmpty)
    }

    @Test func eachCarKeepsItsOwnRangesAndLayout() throws {
        let profiles = CarProfiles(defaults: freshDefaults())
        let a = try #require(profiles.add(make: "BMW", model: "M135i"))
        let b = try #require(profiles.add(make: "Mazda", model: "MX-5"))
        #expect(a.ranges.isEmpty && a.layout == .standard) // a new car starts with the defaults

        var problem: String?
        let typed = GaugeRange(min: 0, max: 8000, rpm: RPMZones(normalLow: 0, normalHigh: 6500, redline: 7200))
        profiles.update(a.id) {
            problem = $0.saveRange(typed: typed, for: .sensor(.rpm), units: Units())
            $0.layout.count = 2
        }
        #expect(problem == nil)
        #expect(profiles.profile(id: a.id)?.range(for: .sensor(.rpm)).rpm?.redline == 7200)
        #expect(profiles.profile(id: b.id)?.range(for: .sensor(.rpm)) == .standard(for: .rpm))
        #expect(profiles.profile(id: b.id)?.layout == .standard)
    }

    @Test func aNewVINCanBeLinkedToACarCreatedByHand() async throws {
        let defaults = freshDefaults()
        let byHand = try #require(CarProfiles(defaults: defaults).add(make: "BMW", model: "M135i"))
        #expect(byHand.vin == nil)

        let scanner = BluetoothScanner(defaults: defaults)
        await scanner.useSimulatedAdapter()
        #expect(scanner.needsCarInfo) // the VIN is new, so it asks
        scanner.linkCar(byHand.id)
        #expect(!scanner.needsCarInfo)
        #expect(scanner.car?.id == byHand.id)
        #expect(scanner.profiles.profile(id: byHand.id)?.vin == SimulatedAdapter.fakeVIN)
        #expect(scanner.profiles.all.count == 1) // linked, not a second car
        #expect(!scanner.log.contains { $0.contains(SimulatedAdapter.fakeVIN) })

        // The next connection knows it.
        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(!scanner.needsCarInfo)
        #expect(scanner.carName == "BMW M135i")

        // A car that already has a VIN is not linked again.
        let other = try #require(scanner.profiles.add(make: "Mazda", model: "MX-5", vin: "OTHERVIN000000002"))
        scanner.linkCar(other.id)
        #expect(scanner.profiles.profile(id: other.id)?.vin == "OTHERVIN000000002")
    }

    @Test func theActiveCarIsTheConnectedOneElseTheLastUsed() async throws {
        let defaults = freshDefaults()
        let saved = CarProfiles(defaults: defaults)
        let byHand = try #require(saved.add(make: "Mazda", model: "MX-5"))
        let linked = try #require(saved.add(make: "BMW", model: "M135i", vin: SimulatedAdapter.fakeVIN))
        saved.use(byHand.id)

        let scanner = BluetoothScanner(defaults: defaults)
        #expect(scanner.profiles.active?.id == byHand.id) // not connected: the last used
        await scanner.useSimulatedAdapter()
        #expect(scanner.profiles.active?.id == linked.id) // connected: the car with this VIN
        scanner.disconnect()
        #expect(scanner.profiles.active?.id == linked.id) // disconnected: still the last used
        scanner.profiles.use(byHand.id) // "Use this car"
        #expect(scanner.profiles.active?.id == byHand.id)
        #expect(CarProfiles(defaults: defaults).active?.id == byHand.id) // kept after a relaunch

        // The last used car deleted: the first one left.
        scanner.deleteCar(byHand.id)
        #expect(scanner.profiles.active?.id == linked.id)
    }

    @Test func theConnectedCarCannotBeDeleted() async throws {
        let defaults = freshDefaults()
        let saved = CarProfiles(defaults: defaults)
        let linked = try #require(saved.add(make: "BMW", model: "M135i", vin: SimulatedAdapter.fakeVIN))
        let other = try #require(saved.add(make: "Mazda", model: "MX-5"))

        let scanner = BluetoothScanner(defaults: defaults)
        await scanner.useSimulatedAdapter()
        #expect(scanner.connectedCarID == linked.id)
        scanner.deleteCar(linked.id)
        #expect(scanner.profiles.profile(id: linked.id) != nil)
        scanner.deleteCar(other.id) // another car can go
        #expect(scanner.profiles.profile(id: other.id) == nil)

        scanner.disconnect()
        #expect(scanner.connectedCarID == nil)
        scanner.deleteCar(linked.id)
        #expect(scanner.profiles.all.isEmpty)
    }

    @Test func pollingFollowsTheActiveCarsLayout() async throws {
        let defaults = freshDefaults()
        let saved = CarProfiles(defaults: defaults)
        let byHand = try #require(saved.add(make: "Mazda", model: "MX-5"))
        let linked = try #require(saved.add(make: "BMW", model: "M135i", vin: SimulatedAdapter.fakeVIN))
        saved.update(byHand.id) { $0.layout = layout(.sensor(.rpm)) }
        saved.update(linked.id) { $0.layout = layout(.sensor(.coolantTemp)) }
        saved.use(byHand.id)

        let scanner = BluetoothScanner(defaults: defaults)
        #expect(scanner.sensorsToPoll == [.rpm])
        let simulated = await scanner.useSimulatedAdapter() // the VIN picks the BMW
        simulated.noDataChance = 0
        #expect(scanner.sensorsToPoll == [.coolantTemp])

        let before = simulated.received.count
        scanner.startPolling()
        let start = ContinuousClock.now
        while scanner.liveData.value(for: .coolantTemp) == nil && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        scanner.stopPolling()
        let asked = simulated.received.dropFirst(before)
        #expect(asked.contains("0105\r"))
        #expect(!asked.contains("010C\r"))

        scanner.disconnect()
        scanner.profiles.use(byHand.id)
        #expect(scanner.sensorsToPoll == [.rpm])
    }

    @Test func theVINShowsOnlyItsLastFourCharacters() {
        let car = CarProfile(vin: SimulatedAdapter.fakeVIN, make: "BMW", model: "M135i")
        #expect(car.vinLabel == "VIN •••• 0001")
        #expect(!car.vinLabel.contains("TESTVIN"))
        #expect(CarProfile(make: "BMW", model: "M135i").vinLabel == "Not linked yet")
    }
}

@MainActor
struct VINStaysOutOfTheLogTests {
    // Hex of the fake VIN's first bytes ("TES"), as they would appear in a log line.
    private let fakeVINHex = "544553"

    @Test func testADoesNotAskForTheVIN() async {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        let asked = simulated.received.count
        await scanner.runTestA()
        // Only the VIN request made when connecting; none from the test.
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 1)
        #expect(simulated.received.count > asked)
        #expect(!scanner.log.contains { $0.contains("0902") || $0.contains(fakeVINHex) || $0.contains(SimulatedAdapter.fakeVIN) })
    }

    @Test func aLateVINAnswerIsHidden() async {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await scanner.useSimulatedAdapter()
        scanner.receive("7E81014490201544553\r7E8215456494E303030\r7E82230303030303031\r\r>") // nobody is waiting for it
        #expect(scanner.log.last?.contains("Late response") == true)
        #expect(!scanner.log.contains { $0.contains(fakeVINHex) })
    }
}
