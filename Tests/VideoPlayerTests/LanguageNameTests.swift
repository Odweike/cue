import XCTest
@testable import VideoPlayer

final class LanguageNameTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testResolvesTwoAndThreeLetterCodes() {
        XCTAssertEqual(LanguageName.displayName(for: "ru", locale: english), "Russian")
        XCTAssertEqual(LanguageName.displayName(for: "rus", locale: english), "Russian")
        XCTAssertEqual(LanguageName.displayName(for: "en", locale: english), "English")
        XCTAssertEqual(LanguageName.displayName(for: "eng", locale: english), "English")
        XCTAssertEqual(LanguageName.displayName(for: "ja", locale: english), "Japanese")
    }

    func testFallsBackToUppercasedCodeForUnknownLanguage() {
        XCTAssertEqual(LanguageName.displayName(for: "zz", locale: english), "ZZ")
    }

    func testTrimsAndNormalizesSeparators() {
        XCTAssertEqual(LanguageName.displayName(for: " RU_ru ", locale: english), "Russian")
    }
}
