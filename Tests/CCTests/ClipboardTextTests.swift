import CCCore
import Testing
@testable import CC

@MainActor
struct ClipboardTextTests {
    private let shelfFixture = ShelfStoreTestFixture()

    @Test func addsNonemptyClipboardTextOnce() {
        let store = shelfFixture.makeStore(errorPresenter: { _ in })

        #expect(store.addClipboardText("  draft note\n") == true)
        #expect(store.addClipboardText("  draft note\n") == false)
        #expect(store.items.count == 1)
        #expect(store.items.first?.kind == .text)
        #expect(store.items.first?.text == "  draft note\n")
    }

    @Test func ignoresMissingOrWhitespaceOnlyClipboardText() {
        let store = shelfFixture.makeStore(errorPresenter: { _ in })

        #expect(store.addClipboardText(nil) == false)
        #expect(store.addClipboardText(" \n\t") == false)
        #expect(store.items.isEmpty)
    }

    @Test(arguments: ["codex", "claude"])
    func addsAHumanHandoffWithTheSameTextAsAnAgent(source: String) throws {
        let text = "Shared draft"
        let agent = try shelfFixture.repository.addText(text, source: source)
        let store = shelfFixture.makeStore()

        #expect(store.canAddClipboardText(text))
        #expect(store.addClipboardText(text))
        #expect(store.items.count == 2)
        #expect(store.items.contains { $0.id == agent.id && $0.source == source })
        #expect(store.items.contains { $0.text == text && $0.source == "human" && $0.note == nil })
        #expect(store.unreadItemIDs == [agent.id])
        #expect(!store.canAddClipboardText(text))
        #expect(!store.addClipboardText(text))
    }

    @Test(arguments: ["Review this revision", ""])
    func addsANoNoteHandoffWhenExistingHumanTextHasANote(note: String) throws {
        let text = "Shared draft"
        let existing = try shelfFixture.repository.addText(text, source: "human", note: note)
        let store = shelfFixture.makeStore()

        #expect(store.canAddClipboardText(text))
        #expect(store.addClipboardText(text))
        #expect(store.items.count == 2)
        #expect(store.items.contains { $0.id == existing.id && $0.note == note })
        #expect(store.items.contains { $0.text == text && $0.source == "human" && $0.note == nil })
        #expect(!store.canAddClipboardText(text))
        #expect(!store.addClipboardText(text))
    }
}
