import Foundation
import Testing
@testable import Context

@MainActor
struct ShelfPresentationPreferenceTests {
    @Test func startsInTheMenuBarAndIgnoresLegacyOrUnknownModes() throws {
        let suite = "ContextTests.presentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ShelfPresentationPreferences(defaults: defaults).mode == .menuBar)
        for rawValue in ["floating", "unknown"] {
            defaults.set(rawValue, forKey: "shelfPresentationMode")
            #expect(ShelfPresentationPreferences(defaults: defaults).mode == .menuBar)
        }
    }

    @Test func keepsTheSelectedModeAcrossRelaunches() throws {
        let suite = "ContextTests.presentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = ShelfPresentationPreferences(defaults: defaults)
        preferences.mode = .notch
        #expect(ShelfPresentationPreferences(defaults: defaults).mode == .notch)
        preferences.mode = .menuBar
        #expect(ShelfPresentationPreferences(defaults: defaults).mode == .menuBar)
    }
}
