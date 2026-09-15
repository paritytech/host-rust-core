import Testing
@testable import Coinage

@Suite("SubscriptionKey Tests")
struct SubscriptionKeyTests {
    @Test("Test member key mapping")
    func memberKeyMapping() {
        let key = SubscriptionKey.member(derivationIndex: 123)
        let mapping = key.mappingKey

        #expect(mapping == "m:123")
        #expect(SubscriptionKey(mappingKey: mapping) == key)
    }

    @Test("Test ringStatus key mapping")
    func ringStatusKeyMapping() {
        let key = SubscriptionKey.ringStatus(derivationIndex: 7)
        let mapping = key.mappingKey

        #expect(mapping == "rs:7")
        #expect(SubscriptionKey(mappingKey: mapping) == key)
    }

    @Test("Test invalid mapping keys return nil")
    func invalidMappingKeys() {
        #expect(SubscriptionKey(mappingKey: "x:123") == nil)
        #expect(SubscriptionKey(mappingKey: "m") == nil)
        #expect(SubscriptionKey(mappingKey: "m:abc") == nil)
        // RecyclerKey.ringStatusMappingKey format ("rs:<exponent>:<index>") must not parse as SubscriptionKey
        #expect(SubscriptionKey(mappingKey: "rs:0:7") == nil)
    }
}
