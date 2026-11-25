import XCTest
@testable import Perroquet

final class AppLanguageTests: XCTestCase {
    private var suiteName = ""

    private func makeDefaults() -> UserDefaults {
        let name = "AppLanguageTests-\(UUID().uuidString)"
        suiteName = name
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testFrenchWritesItsCode() {
        let defaults = makeDefaults()
        AppLanguage.french.store(in: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["fr"])
        XCTAssertEqual(AppLanguage.stored(in: defaults, domain: suiteName), .french)
    }

    func testEnglishWritesItsCode() {
        let defaults = makeDefaults()
        AppLanguage.english.store(in: defaults)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String], ["en"])
        XCTAssertEqual(AppLanguage.stored(in: defaults, domain: suiteName), .english)
    }

    func testSystemRemovesTheKey() {
        let defaults = makeDefaults()
        AppLanguage.french.store(in: defaults)
        AppLanguage.system.store(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(AppLanguage.stored(in: defaults, domain: suiteName), .system)
    }

    func testRegionalVariantMapsToItsLanguage() {
        let defaults = makeDefaults()
        defaults.set(["fr-FR"], forKey: "AppleLanguages")
        XCTAssertEqual(AppLanguage.stored(in: defaults, domain: suiteName), .french)
    }
}
