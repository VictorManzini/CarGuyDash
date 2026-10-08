import CoreBluetooth

/// Owns the Bluetooth central manager. For now it only reports the Bluetooth state.
final class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        // queue: nil delivers delegate callbacks on the main queue.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

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
        print("Found: \(peripheral.name ?? "(no name)") RSSI: \(RSSI) dBm")
    }
}
