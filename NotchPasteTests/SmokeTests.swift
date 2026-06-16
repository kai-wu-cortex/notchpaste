import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test("test target builds")
    func smoke() {
        #expect(1 + 1 == 2)
    }
}
