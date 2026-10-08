import Testing
@testable import CarGuyDash

struct CarTestsTests {
    @Test func nextBlockBitIsRead() {
        #expect(BluetoothScanner.supportsNextBlock("4100BE3EB813\r\r>", for: "0100"))
        #expect(BluetoothScanner.supportsNextBlock("41 20 80 01 A0 01\r\r>", for: "0120"))
        #expect(!BluetoothScanner.supportsNextBlock("4140FED08400\r\r>", for: "0140"))
        // Two ECUs: one is enough.
        #expect(BluetoothScanner.supportsNextBlock("4100BE3EB812\r4100BE3EB811\r\r>", for: "0100"))
        #expect(!BluetoothScanner.supportsNextBlock("NO DATA\r\r>", for: "0100"))
        #expect(!BluetoothScanner.supportsNextBlock("SEARCHING...\rUNABLE TO CONNECT\r\r>", for: "0100"))
        // Answer to another PID does not count.
        #expect(!BluetoothScanner.supportsNextBlock("4120FFFFFFFF\r\r>", for: "0100"))
    }

    @Test func readingsAreRecognized() {
        #expect(BluetoothScanner.dataLines("410C1AF8\r\r>", for: "010C") == ["410C1AF8"])
        #expect(BluetoothScanner.dataLines("NO DATA\r\r>", for: "010C").isEmpty)
        #expect(BluetoothScanner.dataLines("7F 01 12\r\r>", for: "010C").isEmpty)
        // Headers on (ATH1): header and length byte are removed.
        #expect(BluetoothScanner.dataLines("7E804410C1AF8\r7E904410C1AF8\r\r>", for: "010C") == ["410C1AF8", "410C1AF8"])
        #expect(BluetoothScanner.supportsNextBlock("7E8064100BE3FA813\r7E906410098188011\r\r>", for: "0100"))
    }
}
