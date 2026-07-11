import Testing
@testable import BeerKit

@Suite struct SmokeTests {
    @Test func version() {
        #expect(BeerKitInfo.version == "0.1.0")
    }
}
