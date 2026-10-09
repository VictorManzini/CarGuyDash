import Testing
@testable import CarGuyDash

struct GaugeTextTests {
    @Test func standByWhileTheConnectionIsNotUp() {
        for state in [ConnectionState.reconnecting, .connecting, .searching, .bluetoothOff] {
            #expect(gaugeText(for: .rpm, state: state, value: nil) == "Stand By")
            // Even with an old value left over, Stand By wins.
            #expect(gaugeText(for: .rpm, state: state, value: 750) == "Stand By")
        }
    }

    @Test func disconnectedIsNA() {
        #expect(gaugeText(for: .rpm, state: .disconnected, value: nil) == "N/A")
        #expect(gaugeText(for: .rpm, state: .disconnected, value: 750) == "N/A")
    }

    @Test func readyShowsTheNumberOrNA() {
        #expect(gaugeText(for: .rpm, state: .ready, value: 750) == "750")
        #expect(gaugeText(for: .moduleVoltage, state: .ready, value: 13.7) == "13.7")
        #expect(gaugeText(for: .oilTemp, state: .ready, value: nil) == "N/A") // this sensor stopped answering
    }
}
