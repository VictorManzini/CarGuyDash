import CoreBluetooth

/// Scans for the OBD-II adapter, connects to it, lists its services and characteristics,
/// and runs a fixed command sequence through the gatekeeper, printing raw responses.
final class BluetoothScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var adapter: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var responseBuffer = ""
    private var sentAt: ContinuousClock.Instant?

    // Known ELM327 BLE layouts: (service, notify characteristic, write characteristic).
    private let knownPairs: [(service: CBUUID, notify: CBUUID, write: CBUUID)] = [
        (CBUUID(string: "FFF0"), CBUUID(string: "FFF1"), CBUUID(string: "FFF2")),
        (CBUUID(string: "18F0"), CBUUID(string: "2AF0"), CBUUID(string: "2AF1")),
        (CBUUID(string: "FFE0"), CBUUID(string: "FFE1"), CBUUID(string: "FFE1")),
    ]

    // ponytail: fixed test sequence, raw responses only (no decoding yet).
    private var pendingCommands = [
        "ATZ", "ATE0", "ATL0", "ATS0", "ATSP0",
        "0100", "0120", "0140", "010C", "015C", "010B", "0902",
    ]

    override init() {
        super.init()
        // queue: nil delivers delegate callbacks on the main queue.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Central

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth: poweredOn")
            // nil = any service; each device is reported once (no duplicates by default).
            central.scanForPeripherals(withServices: nil)
        case .poweredOff: print("Bluetooth: poweredOff")
        case .unauthorized: print("Bluetooth: unauthorized")
        case .unsupported: print("Bluetooth: unsupported")
        case .resetting: print("Bluetooth: resetting")
        case .unknown: print("Bluetooth: unknown")
        @unknown default: print("Bluetooth: new state \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        print("Found: \(name ?? "(no name)") RSSI: \(RSSI) dBm")

        guard adapter == nil, let name, name.contains("IOS-Vlink") else { return }
        print("Adapter found, connecting to \(name)")
        central.stopScan()
        adapter = peripheral // CoreBluetooth drops the connection if nobody keeps a reference.
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "adapter")")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected: \(error?.localizedDescription ?? "no error")")
    }

    // MARK: - Peripheral

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { print("Service discovery failed: \(error.localizedDescription)"); return }
        for service in peripheral.services ?? [] {
            print("Service \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { print("Characteristic discovery failed: \(error.localizedDescription)"); return }
        let characteristics = service.characteristics ?? []
        for characteristic in characteristics {
            print("  Characteristic \(characteristic.uuid) in \(service.uuid): \(describe(characteristic.properties))")
        }

        // Use the first known layout found; ignore the rest.
        guard writeCharacteristic == nil,
              let pair = knownPairs.first(where: { $0.service == service.uuid }),
              let notify = characteristics.first(where: { $0.uuid == pair.notify }),
              let write = characteristics.first(where: { $0.uuid == pair.write })
        else { return }

        print("Using service \(pair.service): notify \(pair.notify), write \(pair.write)")
        notifyCharacteristic = notify
        writeCharacteristic = write
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { print("Enabling notifications failed: \(error.localizedDescription)"); return }
        guard characteristic == notifyCharacteristic, characteristic.isNotifying else { return }
        print("Notifications on for \(characteristic.uuid)")
        sendNextCommand()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notifyCharacteristic, let data = characteristic.value else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        responseBuffer += chunk

        // The ELM327 ends every response with the ">" prompt.
        guard responseBuffer.contains(">") else { return }
        let elapsed = sentAt.map { Int((ContinuousClock.now - $0) / .milliseconds(1)) } ?? -1
        print("RX (\(elapsed) ms): \(responseBuffer.debugDescription)")
        responseBuffer = ""
        sendNextCommand()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { print("Write failed: \(error.localizedDescription)") }
    }

    // MARK: - Helpers

    private func sendNextCommand() {
        guard !pendingCommands.isEmpty else { print("Test sequence finished"); return }
        send(pendingCommands.removeFirst())
    }

    /// The only place that writes to the adapter. Every command passes the gatekeeper first.
    private func send(_ command: String) {
        guard Gatekeeper.check(command) == .allowed else {
            print("BLOCKED by gatekeeper: \(command.debugDescription)")
            return
        }
        guard let adapter, let write = writeCharacteristic else { return }
        let line = Gatekeeper.normalize(command) + "\r"
        let type: CBCharacteristicWriteType = write.properties.contains(.write) ? .withResponse : .withoutResponse
        print("TX: \(line.debugDescription)")
        sentAt = .now
        adapter.writeValue(Data(line.utf8), for: write, type: type)
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
