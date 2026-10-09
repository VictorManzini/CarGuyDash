import Foundation

/// In-car test mode: fixed command sequences sent through `run`, which uses the gatekeeper.
extension BluetoothScanner {
    /// ATH1 turns headers on, so each answer shows which ECU sent it (7E8 = engine).
    static let setupCommands = ["ATZ", "ATE0", "ATL0", "ATS0", "ATH1", "ATSP0"]

    /// Setup + battery voltage, the supported-PID blocks, then a fixed list of PIDs.
    /// Logs each raw response and its time. Not 0902: the VIN is read on connecting and kept out of the logs.
    func runTestA() async {
        isTesting = true
        defer { isTesting = false }
        addLog("=== Test A ===")
        for command in Self.setupCommands + ["ATRV"] { await runAndLog(command) }

        // 0100, 0120, 0140... while the last bit of the block says the next block exists.
        var block = 0x00
        while block <= 0xE0 {
            let command = String(format: "01%02X", block)
            guard let response = await runAndLog(command),
                  Self.supportsNextBlock(response, for: command) else { break }
            block += 0x20
        }

        for command in ["010C", "015C", "010B", "0105", "010D", "0111", "010F", "0104"] {
            await runAndLog(command)
        }
        addLog("=== Test A finished ===")
    }

    /// Speed test: 010C alone for 10 s, then the 010C/010B/015C/0105 cycle for 10 s.
    /// Logs readings per second for each PID.
    func runTestB() async {
        isTesting = true
        defer { isTesting = false }
        addLog("=== Test B (speed) ===")
        for command in Self.setupCommands { await runAndLog(command) }
        addLog("Phase 1: 010C only, 10 s")
        await measure(["010C"])
        addLog("Phase 2: cycle 010C/010B/015C/0105, 10 s")
        await measure(["010C", "010B", "015C", "0105"])
        addLog("=== Test B finished ===")
    }

    @discardableResult
    private func runAndLog(_ command: String) async -> String? {
        guard let result = await run(command) else { return nil }
        addLog("\(command) (\(result.ms) ms): \(result.response.debugDescription)")
        return result.response
    }

    /// Sends `commands` in a loop for 10 s, counting only valid answers ("41xx...").
    private func measure(_ commands: [String]) async {
        var readings = Dictionary(uniqueKeysWithValues: commands.map { ($0, 0) })
        let start = ContinuousClock.now
        loop: while ContinuousClock.now - start < .seconds(10) {
            for command in commands {
                // Timeout or disconnect: stop, the numbers would be meaningless.
                guard let result = await run(command) else { break loop }
                if !Self.dataLines(result.response, for: command).isEmpty { readings[command, default: 0] += 1 }
            }
        }
        let seconds = Double((ContinuousClock.now - start) / .milliseconds(1)) / 1000
        for command in commands {
            let count = readings[command, default: 0]
            addLog("\(command): \(count) readings in \(String(format: "%.1f", seconds)) s = \(String(format: "%.1f", Double(count) / seconds))/s")
        }
    }

    /// For a support block (0100, 0120...): the last of the 32 bits says the next block is supported.
    /// Any ECU answering "yes" counts.
    nonisolated static func supportsNextBlock(_ response: String, for command: String) -> Bool {
        dataLines(response, for: command).contains { line in
            line.count >= 12 && (line.dropFirst(11).first?.hexDigitValue ?? 0) & 1 == 1
        }
    }

    /// Lines of the response that are a positive answer to `command` ("010C" -> lines starting with "410C").
    /// With headers on, the header and length byte ("7E804") are removed first.
    nonisolated static func dataLines(_ response: String, for command: String) -> [String] {
        let expected = "4" + command.dropFirst()
        return response
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" })
            .map { $0.filter { $0 != " " } }
            .map { $0.hasPrefix("7E") && $0.count > 5 ? String($0.dropFirst(5)) : $0 }
            .filter { $0.hasPrefix(expected) }
    }
}
