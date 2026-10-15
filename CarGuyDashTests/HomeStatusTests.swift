import Testing
@testable import CarGuyDash

struct HomeStatusTests {
    @Test func eachStateHasItsTextAndColor() {
        let expected: [(ConnectionState, GaugeColor?)] = [
            (.ready, .green), (.searching, .blue), (.connecting, .blue),
            (.reconnecting, .orange), (.bluetoothOff, .red), (.disconnected, nil),
        ]
        for (state, color) in expected {
            #expect(HomeStatus(state: state, silent: false) == HomeStatus(text: state.rawValue, color: color))
        }
    }

    @Test func aSilentCarSaysIgnitionOffInYellow() {
        #expect(HomeStatus(state: .ready, silent: true) == HomeStatus(text: "Ignition off?", color: .yellow))
    }
}
