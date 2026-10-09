import Testing
@testable import CarGuyDash

struct SensorTests {
    /// Data bytes from the in-car test log (2026-10-08, engine off).
    @Test(arguments: [
        (Sensor.oilTemp, [0x6B], 67.0),          // 015C -> 415C6B
        (.coolantTemp, [0x6D], 69.0),            // 0105 -> 41056D
        (.manifoldPressure, [0x5D], 93.0),       // 010B -> 410B5D
        (.intakeAirTemp, [0x55], 45.0),          // 010F -> 410F55
        (.rpm, [0x00, 0x00], 0.0),               // 010C -> 410C0000
        (.speed, [0x00], 0.0),                   // 010D -> 410D00
        (.engineLoad, [0x00], 0.0),              // 0104 -> 410400
        (.throttlePosition, [0x4E], 78 * 100 / 255.0), // 0111 -> 41114E
        (.rpm, [0x1A, 0xF8], 1726.0),
    ] as [(Sensor, [UInt8], Double)])
    func formulasMatchTheCarLog(sensor: Sensor, bytes: [UInt8], expected: Double) {
        #expect(sensor.decode(bytes) == expected)
    }

    @Test func tooFewBytesGiveNil() {
        for sensor in Sensor.allCases {
            #expect(sensor.decode([]) == nil, "\(sensor)")
            #expect(sensor.decode(Array(repeating: 0, count: sensor.byteCount)) != nil, "\(sensor)")
        }
    }

    /// Every sensor must be readable through the gatekeeper as "01" + PID.
    @Test func everyPIDPassesTheGatekeeper() {
        for sensor in Sensor.allCases {
            #expect(Gatekeeper.check("01" + sensor.rawValue) == .allowed, "\(sensor)")
        }
    }

    @Test func onlyTheEngineAnswerIsUsed() {
        // Engine (7E8) and gearbox (7E9) answer together, in either order.
        #expect(Sensor.rpm.value(from: "7E804410C1AF8\r7E904410C0000\r\r>") == 1726)
        #expect(Sensor.rpm.value(from: "7E904410C0000\r7E804410C1AF8\r\r>") == 1726)
        #expect(Sensor.coolantTemp.value(from: "7E90341056D\r7E80341056D\r\r>") == 69)
        #expect(Sensor.coolantTemp.value(from: "7E9 03 41 05 50\r7E8 03 41 05 6D\r\r>") == 69)
        #expect(Sensor.oilTemp.value(from: "7E803415C6B\r\r>") == 67)
        #expect(Sensor.manifoldPressure.value(from: "SEARCHING...\r7E803410B5D\r\r>") == 93)
        // Only the gearbox answered: no value.
        #expect(Sensor.rpm.value(from: "7E904410C1AF8\r\r>") == nil)
        // Answer to another PID: no value.
        #expect(Sensor.rpm.value(from: "7E803410D00\r\r>") == nil)
    }

    @Test(arguments: [
        "", "\r\r>", "NO DATA\r\r>", "SEARCHING...\rUNABLE TO CONNECT\r\r>",
        "7E8037F0112\r\r>",   // negative answer
        "7E804410C1A\r\r>",   // RPM with one byte missing
        "7E804410C1AF\r\r>",  // odd number of hex digits
        "7E804410CZZF8\r\r>", // not hex
        "410C1AF8\r\r>",      // headers off (ATH0): ECU unknown
    ])
    func badResponsesGiveNil(_ response: String) {
        #expect(Sensor.rpm.value(from: response) == nil)
    }
}

struct SensorTextTests {
    @Test(arguments: [
        (Sensor.rpm, 1726.0, "1726"),
        (.rpm, 812.75, "813"),
        (.oilTemp, 67.0, "67"),
        (.coolantTemp, 69.4, "69"),
        (.intakeAirTemp, -7.0, "-7"),
        (.manifoldPressure, 93.0, "93"),
        (.throttlePosition, 78 * 100 / 255.0, "31"),
        (.moduleVoltage, 14.1, "14.1"),
        (.moduleVoltage, 12.36, "12.4"),
    ] as [(Sensor, Double, String)])
    func valuesAreFormatted(sensor: Sensor, value: Double, expected: String) {
        #expect(sensor.text(for: value) == expected)
    }

    @Test func noValueIsNA() {
        for sensor in Sensor.allCases {
            #expect(sensor.text(for: nil) == "N/A", "\(sensor)")
        }
    }
}
