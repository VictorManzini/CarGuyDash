import Testing
@testable import CarGuyDash

@MainActor
struct VINTests {
    // The fake VIN "TESTVIN0000000001" as the engine ECU would send it (ATH1, spaces off).
    // Never use the real car's VIN here: the repository is public.
    private let good = "7E81014490201544553\r7E8215456494E303030\r7E82230303030303031\r\r>"

    @Test func decodesTheFakeVIN() {
        #expect(VIN.decode(from: good) == "TESTVIN0000000001")
        // Spaces and lower case do not matter.
        #expect(VIN.decode(from: "7E8 10 14 49 02 01 54 45 53\r7e8 21 54 56 49 4E 30 30 30\r7E8 22 30 30 30 30 30 30 31\r>") == "TESTVIN0000000001")
    }

    @Test func ignoresTheSecondECU() {
        #expect(VIN.decode(from: "7E9101449020100000000\r" + good) == "TESTVIN0000000001")
    }

    @Test func brokenAnswersGiveNoVIN() {
        let broken = [
            "NO DATA\r\r>",
            "",
            "7E81014490201544553\r7E8215456494E303030\r\r>", // line 3 missing
            "7E81014490201544553\r7E8215456494E303030\r7E822303030303030\r>", // line 3 one byte short
            "7E81014490201544553\r7E8215456494E303030\r7E8223030303030303131\r>", // line 3 one byte long
            "7E81014490201544553\r7E8215456494E303030\r7E82330303030303031\r>", // wrong frame number
            "7E81014490101544553\r7E8215456494E303030\r7E82230303030303031\r>", // not 49 02 01
            "7E81014490201544553\r7E8215456494E303030\r7E8223030303030303G1\r>", // not hex
            "7E81014490201544553\r7E8215456494E3030FF\r7E82230303030303031\r>", // not a letter or digit
        ]
        for response in broken {
            #expect(VIN.decode(from: response) == nil, "\(response.debugDescription)")
        }
    }

    @Test func theSimulatedAdapterAnswersWithTheFakeVIN() async throws {
        let scanner = BluetoothScanner()
        await scanner.useSimulatedAdapter()
        let result = try #require(await scanner.run("0902"))
        #expect(VIN.decode(from: result.response) == SimulatedAdapter.fakeVIN)
        #expect(!result.response.contains("7E9")) // only the engine ECU answers
    }
}
