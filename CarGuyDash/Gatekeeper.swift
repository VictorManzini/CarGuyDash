/// Read-only safety gate. Every command sent to the adapter must pass `check` first.
/// Allowlist: anything not explicitly allowed is blocked.
nonisolated enum Gatekeeper {
    enum Verdict: Equatable {
        case allowed
        case blocked
    }

    /// Adapter setup commands we use. All of them only configure how the adapter reads.
    static let allowedATCommands: Set<String> = [
        "ATZ", "ATI", "ATE0", "ATL0", "ATS0", "ATH0", "ATH1", "ATSP0", "ATDP", "ATRV",
    ]

    /// Always blocked, even if the allowlist grows by mistake.
    /// ATPP writes to the adapter's memory; ATSH lets us build arbitrary messages to the car.
    static let blockedPrefixes = ["ATPP", "ATSH"]

    /// Uppercases and removes spaces, so "01 0c" and "010C" are the same command.
    /// Every other character (including "\r" and "\n") is kept, so it fails the checks.
    /// The caller must send this normalized text, so what was checked is exactly what is sent.
    static func normalize(_ command: String) -> String {
        command.uppercased().filter { $0 != " " }
    }

    static func check(_ command: String) -> Verdict {
        let normalized = normalize(command)
        if blockedPrefixes.contains(where: { normalized.hasPrefix($0) }) { return .blocked }
        if allowedATCommands.contains(normalized) { return .allowed }
        if normalized == "0902" { return .allowed } // VIN
        if isService01PID(normalized) { return .allowed }
        return .blocked
    }

    /// Service 01 (current data) followed by exactly two hex digits, e.g. "010C".
    private static func isService01PID(_ command: String) -> Bool {
        command.count == 4
            && command.hasPrefix("01")
            && command.dropFirst(2).allSatisfy { "0123456789ABCDEF".contains($0) }
    }
}
