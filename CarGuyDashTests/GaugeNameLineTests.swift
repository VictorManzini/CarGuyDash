import Foundation
import Testing
@testable import CarGuyDash

struct GaugeNameLineTests {
    @Test func theValueSizeLeavesRoomForTheNameLine() {
        // Height is the smaller side once the name line is taken off: (126 - 26) * 0.2.
        #expect(GaugeLook.valueSize(cell: CGSize(width: 200, height: 126)) == 20)
    }

    @Test func aCellShorterThanTheNameLineHasNoValueSize() {
        #expect(GaugeLook.valueSize(cell: CGSize(width: 200, height: 10)) == 0)
    }
}
