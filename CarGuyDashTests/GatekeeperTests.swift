import Foundation
import Testing
@testable import CarGuyDash

struct GatekeeperTests {
    @Test(arguments: [
        "ATZ", "ATI", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0", "ATDP", "ATRV",
        "atz", "at sp0",
        "0100", "010C", "01 0C", "01 0c", "015C", "010B", "01FF",
        "0902", "09 02",
    ])
    func allowedCommandsPass(_ command: String) {
        #expect(Gatekeeper.check(command) == .allowed)
    }

    @Test(arguments: ["04", "04 00", "0400", " 04", "4"])
    func service04IsBlocked(_ command: String) {
        #expect(Gatekeeper.check(command) == .blocked)
    }

    @Test(arguments: ["ATPP 0C SV 01", "ATPP0CON", "ATPPFFOFF", "atpp 0c sv 01", "AT PP 0C ON"])
    func atppIsBlocked(_ command: String) {
        #expect(Gatekeeper.check(command) == .blocked)
    }

    @Test(arguments: ["ATSH 7E0", "ATSH7DF", "atsh 7e0", "AT SH 7E0"])
    func atshIsBlocked(_ command: String) {
        #expect(Gatekeeper.check(command) == .blocked)
    }

    @Test(arguments: [
        "", " ", "01", "010", "01000", "010G", "01 0C 0D", "0103 04",
        "02 0C", "03", "07", "0A", "0902 01", "09 0A", "22 F1 90", "2E F1 90 00",
        "ATMA", "ATWS", "ATD", "ATSP6", "ATZ\r04", "010C\r04", "ATZ\n", "AT", "STP 33",
        "０１０Ｃ", // fullwidth characters
    ])
    func otherCommandsAreBlocked(_ command: String) {
        #expect(Gatekeeper.check(command) == .blocked)
    }

    /// The longest allowed command has 5 characters, so any random command
    /// of 6 or more characters (without spaces) must be blocked.
    @Test func randomLongCommandsAreBlocked() {
        let alphabet = Array("ATSPHZIEL0123456789ABCDEF\r\n")
        for _ in 0..<5_000 {
            let length = Int.random(in: 6...16)
            let command = String((0..<length).map { _ in alphabet.randomElement()! })
            #expect(Gatekeeper.check(command) == .blocked, "\(command.debugDescription)")
        }
    }

    /// No other path may write to the adapter: `writeValue(` must appear exactly once in the app,
    /// inside BluetoothScanner.send(_:), right after the gatekeeper check.
    @Test func onlyOneWritePathExists() throws {
        let appFolder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "CarGuyDash")
            .resolvingSymlinksInPath()
        let files = try #require(FileManager.default.enumerator(at: appFolder, includingPropertiesForKeys: nil))
        var writes: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let count = source.components(separatedBy: "writeValue(").count - 1
            writes += Array(repeating: url.lastPathComponent, count: count)
        }
        #expect(writes == ["BluetoothScanner.swift"])
    }
}
