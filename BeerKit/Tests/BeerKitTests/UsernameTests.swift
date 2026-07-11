import Testing
@testable import BeerKit

@Suite struct UsernameTests {
    @Test func validLowercases() { #expect(Username.normalize("TimJansen") == "timjansen") }
    @Test func trimsWhitespace() { #expect(Username.normalize("  tim_1 ") == "tim_1") }
    @Test func tooShort() { #expect(Username.normalize("ab") == nil) }
    @Test func tooLong() { #expect(Username.normalize(String(repeating: "a", count: 16)) == nil) }
    @Test func mustStartWithLetter() {
        #expect(Username.normalize("1tim") == nil)
        #expect(Username.normalize("_tim") == nil)
    }
    @Test func rejectsSymbolsAndUnicode() {
        #expect(Username.normalize("tim!") == nil)
        #expect(Username.normalize("tïm") == nil)
    }
}
