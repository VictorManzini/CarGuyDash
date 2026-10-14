import Testing
@testable import CarGuyDash

struct DigitalSizeTests {
    @Test func growsToItsPreferredSizeBelowTheCap() {
        #expect(GaugeLook.digitalSize(preferred: 40, grid: 30) == 40) // cap is 45
    }

    @Test func stopsAtTheCap() {
        #expect(GaugeLook.digitalSize(preferred: 45, grid: 30) == 45)
        #expect(GaugeLook.digitalSize(preferred: 100, grid: 30) == 45)
    }

    @Test func neverSmallerThanTheGridSize() {
        #expect(GaugeLook.digitalSize(preferred: 20, grid: 30) == 30)
    }
}
