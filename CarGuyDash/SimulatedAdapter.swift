import Foundation

/// Pretends to be the ELM327 in the car, so the app can be developed without it.
/// Answers like the car did with headers on (ATH1, spaces off): engine ECU (7E8) and a second ECU (7E9).
/// Like the real link, it only receives lines that already passed the gatekeeper.
final class SimulatedAdapter: AdapterLink {
    /// Every line received, so tests can check what got here.
    private(set) var received: [String] = []
    /// Chance that a PID answers "NO DATA", like the real car now and then.
    var noDataChance = 0.05
    private let deliver: (String) -> Void

    /// Engine ECU data bytes from the in-car log (2026-10-08). RPM is made up on every request.
    static let engineBytes: [String: [UInt8]] = [
        "5C": [0x6B], // oil 67 °C
        "05": [0x6D], // coolant 69 °C
        "0B": [0x5D], // manifold 93 kPa
        "0F": [0x55], // intake air 45 °C
        "11": [0x4E], // throttle 30.6 %
    ]

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
        default: break
        }
        let pid = String(command.dropFirst(2))
        guard command.hasPrefix("01"), let bytes = bytes(for: pid), Double.random(in: 0..<1) >= noDataChance else {
            return "NO DATA"
        }
        // The second ECU answers first with zeros, so a reader that does not filter by 7E8 gets it wrong.
        return [("7E9", bytes.map { _ in UInt8(0) }), ("7E8", bytes)]
            .map { header, data in
                header + String(format: "%02X41", data.count + 2) + pid + data.map { String(format: "%02X", $0) }.joined()
            }
            .joined(separator: "\r")
    }

    private func bytes(for pid: String) -> [UInt8]? {
        guard pid == Sensor.rpm.rawValue else { return Self.engineBytes[pid] }
        let raw = Int.random(in: 750...3000) * 4 // RPM = (A * 256 + B) / 4
        return [UInt8(raw / 256), UInt8(raw % 256)]
    }
}
