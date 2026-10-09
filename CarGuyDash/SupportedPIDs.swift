import Foundation

/// Decodes the answer to a "supported PIDs" block of service 01 (0100, 0120, 0140...).
/// The answer is 4 bytes = 32 bits: the first bit is PID block+1, the last is block+32,
/// and the last one also says whether the next block exists.
nonisolated enum SupportedPIDs {
    /// The PIDs of that block and whether the next block exists, using only the engine ECU (7E8).
    /// Nil if it did not give a valid answer: NO DATA, only another ECU, another block, a wrong size.
    static func decode(block: Int, from response: String) -> (pids: Set<Int>, hasNext: Bool)? {
        let expected = String(format: "41%02X", block)
        for line in response.uppercased().split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" }) {
            let line = line.filter { $0 != " " }
            // "7E8" header + 2-digit length byte, then the answer: "7E806" + "4100" + "BE3FA813".
            guard line.hasPrefix("7E8") else { continue }
            let answer = line.dropFirst(5)
            guard answer.hasPrefix(expected) else { continue }
            let hex = answer.dropFirst(expected.count)
            guard hex.count == 8, hex.allSatisfy(\.isHexDigit), let mask = UInt32(hex, radix: 16) else { return nil }
            let pids = (0..<32).filter { mask & (0x8000_0000 >> $0) != 0 }.map { block + 1 + $0 }
            return (Set(pids), mask & 1 == 1)
        }
        return nil
    }
}
