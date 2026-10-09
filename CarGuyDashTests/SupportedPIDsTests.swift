import Testing
@testable import CarGuyDash

struct SupportedPIDsTests {
    /// The PIDs the engine ECU supports, from docs/project-context.md (blocks 0100 to 0160).
    private let docList: Set<Int> = [
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20,
        0x21, 0x23, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x3C, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x49,
        0x4A, 0x4C, 0x51, 0x56, 0x5C, 0x60, 0x68,
    ]

    @Test func realMasksGiveTheListInTheDocs() throws {
        let answers = [
            (0x00, "7E8064100BE3FA813"), (0x20, "7E8064120A007B011"),
            (0x40, "7E8064140FED08411"), (0x60, "7E806416001000000"),
        ]
        var pids = Set<Int>()
        for (block, response) in answers {
            let decoded = try #require(SupportedPIDs.decode(block: block, from: response + "\r\r>"))
            pids.formUnion(decoded.pids)
            // The last bit says whether the next block exists: only 0160 is the end.
            #expect(decoded.hasNext == (block != 0x60), "block \(block)")
        }
        #expect(pids == docList)
    }

    @Test func theSecondECUIsIgnored() throws {
        // 7E9 answers first, with another mask: only 7E8 counts.
        let both = "7E9064100FFFFFFFF\r7E8064100BE3FA813\r\r>"
        let decoded = try #require(SupportedPIDs.decode(block: 0x00, from: both))
        #expect(decoded.pids.contains(0x0C) && !decoded.pids.contains(0x02))
        // Only 7E9 answering is the same as no answer.
        #expect(SupportedPIDs.decode(block: 0x00, from: "7E9064100BE3FA813\r\r>") == nil)
        // The zeros of the second ECU on its own say "nothing supported", not "next block".
        let zeros = try #require(SupportedPIDs.decode(block: 0x00, from: "7E8064100" + "00000000"))
        #expect(zeros.pids.isEmpty && !zeros.hasNext)
    }

    @Test func brokenAnswersGiveNil() {
        let broken = [
            "NO DATA\r\r>", "", "UNABLE TO CONNECT\r\r>",
            "7E8064120A007B011\r\r>", // answer to another block
            "7E8064100BE3FA8\r\r>", // too short
            "7E8064100BE3FA81300\r\r>", // too long
            "7E8064100BE3FA8G3\r\r>", // not hex
        ]
        for response in broken {
            #expect(SupportedPIDs.decode(block: 0x00, from: response) == nil, "\(response.debugDescription)")
        }
    }
}
