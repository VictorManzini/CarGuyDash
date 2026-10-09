import CoreBluetooth
import Foundation
import Observation
import UIKit

/// Whoever carries an approved command to the adapter: the real Bluetooth one or the simulated one.
/// Only `BluetoothScanner.send(_:)` calls `write`, after the gatekeeper approved the command.
/// Responses come back through `BluetoothScanner.receive(_:)`.
protocol AdapterLink {
    func write(_ line: String)
}

/// The real adapter, over Bluetooth.
struct BluetoothLink: AdapterLink {
    let peripheral: CBPeripheral
    let characteristic: CBCharacteristic

    func write(_ line: String) {
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(line.utf8), for: characteristic, type: type)
    }
}

/// Where the connection to the adapter stands. The raw value is shown on screen.
enum ConnectionState: String {
    case bluetoothOff = "Bluetooth off"
    case searching = "Searching"
    case connecting = "Connecting"
    case ready = "Ready"
    case reconnecting = "Reconnecting"
    /// The user tapped Disconnect: nothing reconnects until Connect.
    case disconnected = "Disconnected"
}

/// Scans for the OBD-II adapter, connects to it, lists its services and characteristics,
/// and sends commands through the gatekeeper. Everything is logged on screen and to a file.
@Observable
final class BluetoothScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Every log line of this run, shown on screen and saved to `logFileURL`.
    private(set) var log: [String] = []
    private(set) var state = ConnectionState.bluetoothOff {
        didSet {
            guard state != oldValue else { return }
            addLog("State: \(oldValue.rawValue) → \(state.rawValue)")
            wakeStateWaiter()
        }
    }
    /// True once the adapter can receive commands.
    var isReady: Bool { state == .ready }
    /// True while a car test is running.
    var isTesting = false
    /// Latest sensor values, filled by the polling loop.
    let liveData = LiveData()
    /// The saved cars (only on this iPhone).
    let profiles: CarProfiles
    /// The car of the current connection; nil = no VIN or not named yet ("Unknown car").
    private(set) var car: CarProfile?
    /// VIN of the current connection; nil if the car did not answer. Never logged: the logs get pasted around.
    private(set) var vin: String?
    /// True when the VIN is new and the app waits for make and model.
    private(set) var needsCarInfo = false
    /// "Make Model" of the current car, or "Unknown car".
    var carName: String { car?.name ?? "Unknown car" }
    /// PIDs the engine ECU supports, discovered on every connection (not saved).
    /// Nil: discovery failed or not done yet, so polling uses the fixed list.
    private(set) var supportedPIDs: Set<Int>?
    /// The running polling loop; nil when stopped.
    var pollingTask: Task<Void, Never>?
    /// Counts the valid readings of the current measurement window (see `ReadingMeter`).
    @ObservationIgnored var meter = ReadingMeter()
    /// How often the measurement line is written. Tests shorten it.
    @ObservationIgnored var meterInterval = Duration.seconds(10)
    /// Whether the app is on screen; set by `setAppPhase`.
    private(set) var appPhase: AppPhase
    private let defaults: UserDefaults
    /// Saved on the iPhone each time the app goes to the background: was polling on? Read after a restore.
    private static let pollingWasOnKey = "pollingWasOnInBackground"
    /// One log file per app launch, in the app's Documents folder.
    let logFileURL: URL
    private let timeFormatter = DateFormatter()
    @ObservationIgnored private var logFile: FileHandle?
    @ObservationIgnored private var pendingResponse: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var stateWaiter: CheckedContinuation<Void, Never>?

    private var centralManager: CBCentralManager!
    private var adapter: CBPeripheral?
    private var link: AdapterLink?
    /// Set while the simulated adapter is in use; the real Bluetooth is then ignored.
    private(set) var simulator: SimulatedAdapter?
    private var notifyCharacteristic: CBCharacteristic?
    private var responseBuffer = ""

    // Known ELM327 BLE layouts: (service, notify characteristic, write characteristic).
    private let knownPairs: [(service: CBUUID, notify: CBUUID, write: CBUUID)] = [
        (CBUUID(string: "FFF0"), CBUUID(string: "FFF1"), CBUUID(string: "FFF2")),
        (CBUUID(string: "18F0"), CBUUID(string: "2AF0"), CBUUID(string: "2AF1")),
        (CBUUID(string: "FFE0"), CBUUID(string: "FFE1"), CBUUID(string: "FFE1")),
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = CarProfiles(defaults: defaults)
        // A background relaunch (state restoration) starts here too, so ask instead of assuming "active".
        appPhase = UIApplication.shared.applicationState == .background ? .background : .active
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss.SSS"
        logFileURL = URL.documentsDirectory.appending(path: "log-\(formatter.string(from: .now)).txt")
        FileManager.default.createFile(atPath: logFileURL.path(), contents: nil)
        logFile = try? FileHandle(forWritingTo: logFileURL)
        super.init()
        // queue: nil delivers delegate callbacks on the main queue.
        // The restore identifier lets iOS relaunch the app in the background and hand the connection back (see `restore`).
        centralManager = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.victormanzini.CarGuyDash.central"]
        )
    }

    // MARK: - Central

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard simulator == nil else { return }
        switch central.state {
        case .poweredOn:
            addLog("Bluetooth: poweredOn")
            // After Disconnect, Bluetooth coming back does not connect anything.
            if state != .disconnected { findAdapter(afterBluetoothOn: true) }
            return
        case .poweredOff: addLog("Bluetooth: poweredOff")
        case .unauthorized: addLog("Bluetooth: unauthorized")
        case .unsupported: addLog("Bluetooth: unsupported")
        case .resetting: addLog("Bluetooth: resetting")
        case .unknown: addLog("Bluetooth: unknown")
        @unknown default: addLog("Bluetooth: new state \(central.state.rawValue)")
        }
        guard state != .disconnected else { return }
        connectionLost(to: .bluetoothOff)
    }

    /// iOS closed the app in the background and relaunched it for this adapter. Runs before `centralManagerDidUpdateState`.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        restore(dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [])
    }

    /// Takes the adapter iOS kept for us as the known one; the usual Bluetooth-on path then connects to it.
    /// Polling starts again if it was on when the app went to the background (Stop or Disconnect turn it off).
    func restore(_ peripherals: [CBPeripheral]) {
        if let peripheral = peripherals.first {
            addLog("State restored by iOS: \(peripheral.name ?? "adapter") (was already connected: \(peripheral.state == .connected))")
            adapter = peripheral
            peripheral.delegate = self
        } else {
            addLog("State restored by iOS: no adapter in it")
        }
        if defaults.bool(forKey: Self.pollingWasOnKey) {
            addLog("Polling resumed after restore")
            startPolling() // waits for Ready by itself
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        addLog("Found: \(name ?? "(no name)") RSSI: \(RSSI) dBm")

        guard adapter == nil, simulator == nil, let name, name.contains("IOS-Vlink") else { return }
        addLog("Adapter found, connecting to \(name)")
        central.stopScan()
        state = .connecting
        adapter = peripheral // CoreBluetooth drops the connection if nobody keeps a reference.
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("Connected to \(peripheral.name ?? "adapter")")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        reconnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("Disconnected: \(error?.localizedDescription ?? "no error")")
        guard state != .disconnected else { return } // the user's Disconnect: already cleaned up
        connectionLost()
        reconnect(peripheral)
    }

    // MARK: - Peripheral

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { addLog("Service discovery failed: \(error.localizedDescription)"); return }
        for service in peripheral.services ?? [] {
            addLog("Service \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { addLog("Characteristic discovery failed: \(error.localizedDescription)"); return }
        let characteristics = service.characteristics ?? []
        for characteristic in characteristics {
            addLog("  Characteristic \(characteristic.uuid) in \(service.uuid): \(describe(characteristic.properties))")
        }

        // Use the first known layout found; ignore the rest.
        guard link == nil,
              let pair = knownPairs.first(where: { $0.service == service.uuid }),
              let notify = characteristics.first(where: { $0.uuid == pair.notify }),
              let write = characteristics.first(where: { $0.uuid == pair.write })
        else { return }

        addLog("Using service \(pair.service): notify \(pair.notify), write \(pair.write)")
        notifyCharacteristic = notify
        link = BluetoothLink(peripheral: peripheral, characteristic: write)
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { addLog("Enabling notifications failed: \(error.localizedDescription)"); return }
        guard characteristic == notifyCharacteristic, characteristic.isNotifying else { return }
        addLog("Notifications on for \(characteristic.uuid)")
        Task { await prepare() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notifyCharacteristic, let data = characteristic.value else { return }
        receive(String(decoding: data, as: UTF8.self))
    }

    /// Collects pieces of the answer from either link until the ">" prompt.
    func receive(_ chunk: String) {
        responseBuffer += chunk

        // The ELM327 ends every response with the ">" prompt.
        guard responseBuffer.contains(">") else { return }
        let response = responseBuffer
        responseBuffer = ""
        if pendingResponse == nil {
            // A late answer to 0902 (service 09 PID 02 = "490201...") is the VIN: keep it out of the log.
            addLog("Late response (ignored): \(response.contains("490201") ? "(VIN, hidden)" : response.debugDescription)")
        }
        finishCommand(with: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { addLog("Write failed: \(error.localizedDescription)") }
    }

    // MARK: - Connection

    /// The link is gone: forget it, drop the command in progress, every value becomes N/A.
    /// `newState` is set here so the log shows one state change, not a detour through `.reconnecting`.
    private func connectionLost(to newState: ConnectionState = .reconnecting) {
        link = nil
        notifyCharacteristic = nil
        responseBuffer = ""
        finishCommand(with: nil)
        liveData.clear()
        state = newState
    }

    /// Connects to the known adapter (found by the iPhone's identifier for it),
    /// or searches for any IOS-Vlink if there is none yet.
    private func findAdapter(afterBluetoothOn: Bool) {
        guard let known = adapter,
              let peripheral = centralManager.retrievePeripherals(withIdentifiers: [known.identifier]).first
        else {
            state = .searching
            // nil = any service; each device is reported once (no duplicates by default).
            centralManager.scanForPeripherals(withServices: nil)
            return
        }
        let name = peripheral.name ?? "adapter"
        addLog(afterBluetoothOn ? "Bluetooth back on, reconnecting to \(name)" : "Connecting to \(name)")
        state = afterBluetoothOn ? .reconnecting : .connecting
        adapter = peripheral
        peripheral.delegate = self
        if peripheral.state == .connected {
            peripheral.discoverServices(nil) // restored still connected: no connect needed
        } else {
            centralManager.connect(peripheral)
        }
    }

    /// The user's Disconnect: stops polling, drops the connection and does not reconnect.
    func disconnect() {
        guard state != .disconnected else { return }
        addLog("Disconnect")
        stopPolling()
        connectionLost(to: .disconnected)
        centralManager.stopScan()
        if let adapter { centralManager.cancelPeripheralConnection(adapter) } // also cancels a pending connect
    }

    /// The user's Connect, after a Disconnect: the same adapter again (real or simulated).
    func connect() {
        guard state == .disconnected else { return }
        addLog("Connect")
        if let simulator {
            link = simulator
            state = .connecting
            Task { await prepare() }
        } else if centralManager.state == .poweredOn {
            findAdapter(afterBluetoothOn: false)
        } else {
            state = .bluetoothOff // connects by itself once Bluetooth is on
        }
    }

    /// Asks CoreBluetooth to connect to the same adapter again. A pending connect never times out,
    /// so this keeps trying for as long as it takes.
    private func reconnect(_ peripheral: CBPeripheral) {
        guard peripheral == adapter, state != .disconnected, centralManager.state == .poweredOn else { return }
        addLog("Reconnecting to \(peripheral.name ?? "adapter")")
        centralManager.connect(peripheral)
    }

    /// Runs the setup commands (with ATH1) on every new connection, reads the VIN and the supported PIDs,
    /// then marks it ready. Both come before "ready" so they never compete with the polling loop for the adapter.
    /// Polling, if on, picks up again by itself once the state is ready.
    private func prepare() async {
        for command in Self.setupCommands {
            _ = await run(command)
            guard link != nil else { return } // dropped again during setup
        }
        await readVIN()
        await discoverSupportedPIDs()
        guard link != nil else { return } // dropped again while reading the VIN or the PIDs
        state = .ready
        addLog("Ready")
    }

    /// Asks for the VIN (once per connection) and looks the car up. No VIN: carries on as "Unknown car".
    private func readVIN() async {
        needsCarInfo = false
        // Short timeout: a car that does not answer must not hold up the readings.
        let result = await run("0902", timeout: .seconds(3))
        vin = result.flatMap { VIN.decode(from: $0.response) }
        car = vin.flatMap { profiles.profile(for: $0) }
        if vin == nil {
            addLog("VIN: not available")
        } else if car == nil {
            addLog("VIN: new car, asking for make and model")
            needsCarInfo = true
        } else {
            addLog("VIN: known car")
        }
    }

    /// Asks 0100, 0120, 0140... while the last bit says the next block exists.
    /// Any block without a valid answer from the engine ECU: give up and keep the fixed list (nil).
    private func discoverSupportedPIDs() async {
        var found = Set<Int>()
        var block = 0x00
        while block <= 0xE0 {
            guard let result = await run(String(format: "01%02X", block), timeout: .seconds(3)),
                  let decoded = SupportedPIDs.decode(block: block, from: result.response)
            else {
                addLog("Supported PIDs: no valid answer, using the fixed list")
                supportedPIDs = nil
                return
            }
            found.formUnion(decoded.pids)
            guard decoded.hasNext else { break }
            block += 0x20
        }
        supportedPIDs = found
        addLog("Supported PIDs: \(found.count) found")
    }

    /// Saves make and model for the VIN just read (the "new car" screen's Save button).
    func saveCar(make: String, model: String) {
        let make = make.trimmingCharacters(in: .whitespaces), model = model.trimmingCharacters(in: .whitespaces)
        guard let vin, !make.isEmpty, !model.isEmpty else { return }
        let profile = CarProfile(vin: vin, make: make, model: model)
        profiles.save(profile)
        car = profile
        needsCarInfo = false
        addLog("Car profile saved") // never the VIN, make or model: the logs get pasted around
    }

    /// The new-car screen was closed without saving: "Unknown car" until the next connection asks again.
    func skipCarInfo() {
        guard needsCarInfo else { return } // also called after Save closes the sheet
        needsCarInfo = false
        addLog("Car profile sheet closed without saving")
    }

    // MARK: - Helpers

    /// Stops looking for the real adapter and talks to the simulated one instead.
    /// Returns it so tests can see what it received.
    @discardableResult
    func useSimulatedAdapter() async -> SimulatedAdapter {
        centralManager.stopScan()
        let simulated = SimulatedAdapter { [weak self] in self?.receive($0) }
        simulator = simulated
        link = simulated
        state = .connecting
        addLog("Using the simulated adapter")
        await prepare()
        return simulated
    }

    /// Drops the simulated connection and brings it back after `downtime`, like the real adapter would.
    func simulateDisconnect(for downtime: Duration = .seconds(3)) {
        guard let simulator, isReady else { return }
        addLog("Disconnected (simulated)")
        connectionLost()
        Task {
            try? await Task.sleep(for: downtime)
            guard state == .reconnecting else { return } // Disconnect was tapped meanwhile
            addLog("Reconnected (simulated)")
            link = simulator
            await prepare()
        }
    }

    /// The app went to the background or came back. The measurement window under way is closed first,
    /// so each line belongs to one phase only.
    func setAppPhase(_ phase: AppPhase) {
        guard phase != appPhase else { return }
        if isPolling { addLog(meter.close(in: appPhase)) }
        if phase == .background { defaults.set(wantsPolling, forKey: Self.pollingWasOnKey) }
        appPhase = phase
        addLog(phase == .background ? "App went to the background" : "App back in the foreground")
    }

    /// Appends a line to the screen log and the log file (and the console, for SweetPad).
    func addLog(_ line: String) {
        let line = timeFormatter.string(from: .now) + " " + line
        print(line)
        log.append(line)
        logFile?.write(Data((line + "\n").utf8))
    }

    /// Sends one command and waits for the ">" prompt.
    /// What normally moves on is the adapter's answer (the ELM327 answers every command, even "NO DATA", by itself).
    /// The timer is only the safety net for a lost answer; in the background it can fire late, never too early.
    /// Returns the raw response and the time in ms; nil if blocked, not ready or timed out.
    func run(_ command: String, timeout: Duration = .seconds(10)) async -> (response: String, ms: Int)? {
        guard pendingResponse == nil else { addLog("Busy, not sent: \(command)"); return nil }
        guard send(command) else { return nil }
        let start = ContinuousClock.now
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { finishCommand(with: nil) }
        }
        let response = await withCheckedContinuation { pendingResponse = $0 }
        timeoutTask.cancel()
        guard let response else { addLog("TIMEOUT or disconnected: \(command)"); return nil }
        return (response, Int((ContinuousClock.now - start) / .milliseconds(1)))
    }

    /// Suspends until the connection state changes (or `wakeStateWaiter` is called). No timer involved,
    /// so it cannot run late in the background: the polling loop waits here while not ready.
    func waitForStateChange() async {
        await withCheckedContinuation { stateWaiter = $0 }
    }

    func wakeStateWaiter() {
        stateWaiter?.resume()
        stateWaiter = nil
    }

    private func finishCommand(with response: String?) {
        pendingResponse?.resume(returning: response)
        pendingResponse = nil
    }

    /// The only place that writes to the adapter. Every command passes the gatekeeper first.
    private func send(_ command: String) -> Bool {
        guard Gatekeeper.check(command) == .allowed else {
            addLog("BLOCKED by gatekeeper: \(command.debugDescription)")
            return false
        }
        guard let link else {
            addLog("Not connected, not sent: \(command)")
            return false
        }
        link.write(Gatekeeper.normalize(command) + "\r")
        return true
    }

    private func describe(_ properties: CBCharacteristicProperties) -> String {
        let names: [(CBCharacteristicProperties, String)] = [
            (.read, "read"), (.write, "write"),
            (.writeWithoutResponse, "writeWithoutResponse"), (.notify, "notify"),
        ]
        let found = names.filter { properties.contains($0.0) }.map(\.1)
        return found.isEmpty ? "(none of read/write/notify)" : found.joined(separator: ", ")
    }
}
