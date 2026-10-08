import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct LiveDataTests {
    @Test func oldValueBecomesNA() {
        let liveData = LiveData()
        var clock = Date(timeIntervalSince1970: 0)
        liveData.now = { clock }

        #expect(liveData.value(for: .oilTemp) == nil) // never read
        liveData.record(67, for: .oilTemp)
        clock += 2
        #expect(liveData.value(for: .oilTemp) == 67) // exactly 2 s: still valid
        clock += 0.1
        #expect(liveData.value(for: .oilTemp) == nil) // more than 2 s: N/A

        // No answer (nil) does not refresh the time.
        liveData.record(nil, for: .oilTemp)
        #expect(liveData.value(for: .oilTemp) == nil)
        liveData.record(68, for: .oilTemp)
        #expect(liveData.value(for: .oilTemp) == 68)
    }
}
