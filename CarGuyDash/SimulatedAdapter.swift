import Foundation

/// Pretends to be the ELM327 in the car, so the app can be developed without it.
/// Answers like the car did with headers on (ATH1, spaces off): engine ECU (7E8) and a second ECU (7E9).
/// Like the real link, it only receives lines that already passed the gatekeeper.
final class SimulatedAdapter: AdapterLink {
    /// Every line received, so tests can check what got here.
    private(set) var received: [String] = []
    /// Chance that a PID answers "NO DATA", like the real car now and then.
    var noDataChance = 0.05
    /// False: 0902 answers "NO DATA", like a car that does not give its VIN.
    var answersVIN = true
    /// False: the support blocks (0100, 0120...) answer "NO DATA", like a car that fails to list its PIDs.
    var answersSupportedPIDs = true
    /// "Supported PIDs" masks of the engine ECU (7E8), from the in-car log (no personal data).
    /// A test can change one to make the car lack a sensor.
    var supportMasks: [String: [UInt8]] = [
        "00": [0xBE, 0x3F, 0xA8, 0x13],
        "20": [0xA0, 0x07, 0xB0, 0x11],
        "40": [0xFE, 0xD0, 0x84, 0x11],
        "60": [0x01, 0x00, 0x00, 0x00],
    ]
    private let deliver: (String) -> Void

    /// Engine ECU data bytes from the in-car log (2026-10-08). RPM is made up on every request.
    static let engineBytes: [String: [UInt8]] = [
        "5C": [0x6B], // oil 67 °C
        "05": [0x6D], // coolant 69 °C
        "0B": [0x5D], // manifold 93 kPa
        "0F": [0x55], // intake air 45 °C
        "11": [0x4E], // throttle 30.6 %
        "42": [0x37, 0x14], // module voltage 14.1 V (made up: not read in the car yet)
    ]

    /// A made-up VIN, obviously fake. Never put the real car's VIN in the code, tests or docs: the repository is public.
    static let fakeVIN = "TESTVIN0000000001"

    /// `deliver` gets the full response, as the real adapter sends it back.
    init(deliver: @escaping (String) -> Void) {
        self.deliver = deliver
    }

    func write(_ line: String) {
        received.append(line)
        let response = answer(to: line.trimmingCharacters(in: .newlines))
        Task {
            try? await Task.sleep(for: .milliseconds(100)) // about what the real adapter takes
            deliver(response + "\r\r>")
        }
    }

    private func answer(to command: String) -> String {
        switch command {
        case "ATZ", "ATI": return "ELM327 v2.3"
        case "ATRV": return "12.4V"
        case _ where command.hasPrefix("AT"): return "OK"
        case "0902": return answersVIN ? vinResponse() : "NO DATA"
        default: break
        }
        let pid = String(command.dropFirst(2))
        // The support blocks always answer (never "NO DATA" by chance). The second ECU answers 0100–0140 too, with zeros.
        if command.hasPrefix("01"), let mask = supportMasks[pid] {
            return answersSupportedPIDs ? reply(pid: pid, data: mask, secondECU: pid != "60") : "NO DATA"
        }
        guard command.hasPrefix("01"), let bytes = bytes(for: pid), Double.random(in: 0..<1) >= noDataChance else {
            return "NO DATA"
        }
        return reply(pid: pid, data: bytes, secondECU: true)
    }

    /// The lines of a positive answer. The second ECU answers first with zeros,
    /// so a reader that does not filter by 7E8 gets it wrong.
    private func reply(pid: String, data: [UInt8], secondECU: Bool) -> String {
        (secondECU ? [("7E9", data.map { _ in UInt8(0) }), ("7E8", data)] : [("7E8", data)])
            .map { header, data in
                header + String(format: "%02X41", data.count + 2) + pid + data.map { String(format: "%02X", $0) }.joined()
            }
            .joined(separator: "\r")
    }

    /// Three frames from the engine ECU only (7E8), like the car: 3 + 7 + 7 VIN bytes.
    private func vinResponse() -> String {
        let hex = Self.fakeVIN.utf8.map { String(format: "%02X", $0) }
        let first = hex[0..<3].joined(), second = hex[3..<10].joined(), third = hex[10..<17].joined()
        return ["7E8" + "1014" + "490201" + first, "7E8" + "21" + second, "7E8" + "22" + third].joined(separator: "\r")
    }

    private func bytes(for pid: String) -> [UInt8]? {
        guard pid == Sensor.rpm.rawValue else { return Self.engineBytes[pid] }
        let raw = Int.random(in: 750...3000) * 4 // RPM = (A * 256 + B) / 4
        return [UInt8(raw / 256), UInt8(raw % 256)]
    }
}
