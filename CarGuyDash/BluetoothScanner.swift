import CoreBluetooth
import Foundation
import Observation

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

/// Scans for the OBD-II adapter, connects to it, lists its services and characteristics,
/// and sends commands through the gatekeeper. Everything is logged on screen and to a file.
@Observable
final class BluetoothScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Every log line of this run, shown on screen and saved to `logFileURL`.
    private(set) var log: [String] = []
    /// True once notifications are on and the adapter can receive commands.
    private(set) var isReady = false
    /// True while a car test is running.
    var isTesting = false
    /// Latest sensor values, filled by the polling loop.
    let liveData = LiveData()
    /// The running polling loop; nil when stopped.
    var pollingTask: Task<Void, Never>?
    /// One log file per app launch, in the app's Documents folder.
    let logFileURL: URL
    @ObservationIgnored private var logFile: FileHandle?
    @ObservationIgnored private var pendingResponse: CheckedContinuation<String?, Never>?

    private var centralManager: CBCentralManager!
    private var adapter: CBPeripheral?
    private var link: AdapterLink?
    private var notifyCharacteristic: CBCharacteristic?
    private var responseBuffer = ""

    // Known ELM327 BLE layouts: (service, notify characteristic, write characteristic).
    private let knownPairs: [(service: CBUUID, notify: CBUUID, write: CBUUID)] = [
        (CBUUID(string: "FFF0"), CBUUID(string: "FFF1"), CBUUID(string: "FFF2")),
        (CBUUID(string: "18F0"), CBUUID(string: "2AF0"), CBUUID(string: "2AF1")),
        (CBUUID(string: "FFE0"), CBUUID(string: "FFE1"), CBUUID(string: "FFE1")),
    ]

    override init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        logFileURL = URL.documentsDirectory.appending(path: "log-\(formatter.string(from: .now)).txt")
        FileManager.default.createFile(atPath: logFileURL.path(), contents: nil)
        logFile = try? FileHandle(forWritingTo: logFileURL)
        super.init()
        // queue: nil delivers delegate callbacks on the main queue.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Central

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            addLog("Bluetooth: poweredOn")
            // nil = any service; each device is reported once (no duplicates by default).
            central.scanForPeripherals(withServices: nil)
        case .poweredOff: addLog("Bluetooth: poweredOff")
        case .unauthorized: addLog("Bluetooth: unauthorized")
        case .unsupported: addLog("Bluetooth: unsupported")
        case .resetting: addLog("Bluetooth: resetting")
        case .unknown: addLog("Bluetooth: unknown")
        @unknown default: addLog("Bluetooth: new state \(central.state.rawValue)")
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

        guard adapter == nil, link == nil, let name, name.contains("IOS-Vlink") else { return }
        addLog("Adapter found, connecting to \(name)")
        central.stopScan()
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
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("Disconnected: \(error?.localizedDescription ?? "no error")")
        isReady = false
        finishCommand(with: nil)
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
        isReady = true
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
        if pendingResponse == nil { addLog("Late response (ignored): \(response.debugDescription)") }
        finishCommand(with: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { addLog("Write failed: \(error.localizedDescription)") }
    }

    // MARK: - Helpers

    /// Stops looking for the real adapter and talks to the simulated one instead.
    /// Returns it so tests can see what it received.
    @discardableResult
    func useSimulatedAdapter() -> SimulatedAdapter {
        centralManager.stopScan()
        let simulated = SimulatedAdapter { [weak self] in self?.receive($0) }
        link = simulated
        isReady = true
        addLog("Using the simulated adapter")
        return simulated
    }

    /// Appends a line to the screen log and the log file (and the console, for SweetPad).
    func addLog(_ line: String) {
        print(line)
        log.append(line)
        logFile?.write(Data((line + "\n").utf8))
    }

    /// Sends one command and waits for the ">" prompt.
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
        guard let link, isReady else {
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
