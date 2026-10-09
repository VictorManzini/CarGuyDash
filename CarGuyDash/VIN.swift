import Foundation

/// Decodes the answer to service 09 PID 02 (the VIN).
/// With headers on and spaces off, the engine ECU (7E8) answers in three lines:
///   7E8 10 14 490201 + 3 VIN bytes
///   7E8 21 + 7 VIN bytes
///   7E8 22 + 7 VIN bytes
/// The bytes are ASCII letters and digits.
nonisolated enum VIN {
    /// The 17 characters, or nil for anything else: "NO DATA", a missing or extra line, a wrong size.
    static func decode(from response: String) -> String? {
        let lines = response.uppercased()
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" })
            .map { $0.filter { $0 != " " } }
            .filter { $0.hasPrefix("7E8") } // other ECUs are ignored
        // Each line: 3 (header) + 2 (frame) + [2 (length) + 6 (49 02 01) on the first] + the VIN bytes.
        guard lines.count == 3,
              lines[0].hasPrefix("7E81014490201"), lines[0].count == 19,
              lines[1].hasPrefix("7E821"), lines[1].count == 19,
              lines[2].hasPrefix("7E822"), lines[2].count == 19
        else { return nil }

        let hex = Array(lines[0].dropFirst(13) + lines[1].dropFirst(5) + lines[2].dropFirst(5))
        var vin = ""
        for i in stride(from: 0, to: hex.count, by: 2) {
            guard let byte = UInt8(String(hex[i...i + 1]), radix: 16) else { return nil }
            let character = Character(UnicodeScalar(byte))
            guard character.isASCII, character.isLetter || character.isNumber else { return nil }
            vin.append(character)
        }
        return vin.count == 17 ? vin : nil
    }
}
