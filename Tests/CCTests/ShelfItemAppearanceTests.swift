import Foundation
import Testing
@testable import CC

struct ShelfItemAppearanceTests {
    @Test func distinguishesTheSameFilenameByItsParentFolder() {
        let draft = ShelfItem(kind: .file, title: "Short", detail: "", url: URL(fileURLWithPath: "/Projects/Drafts/Proposal.pdf"))
        let final = ShelfItem(kind: .file, title: "Short", detail: "", url: URL(fileURLWithPath: "/Projects/Final/Proposal.pdf"))
        #expect(ShelfItemAppearance(item: draft).title == "Proposal.pdf")
        #expect(ShelfItemAppearance(item: draft).subtitle == "You · PDF · Drafts")
        #expect(ShelfItemAppearance(item: final).subtitle == "You · PDF · Final")
        #expect(ShelfItemAppearance(item: draft).help.contains("/Projects/Drafts/Proposal.pdf"))
    }

    @Test func hidesTheInternalInboxPathFromImportedFileDetails() {
        let item = ShelfItem(kind: .image, title: "image.png", detail: "Imported from Drop", url: URL(fileURLWithPath: "/cc/Inbox/private-id/image.png"), isManagedFile: true)
        #expect(ShelfItemAppearance(item: item).subtitle == "You · PNG")
        #expect(ShelfItemAppearance(item: item).title == "image.png")
    }

    @Test func describesLinksTextAndFolders() {
        let link = ShelfItem(kind: .link, title: "Reference", detail: "", url: URL(string: "https://example.com/reference"))
        let text = ShelfItem(kind: .text, title: "Note", detail: "", text: "cc:")
        let folder = ShelfItem(kind: .folder, title: "References", detail: "", url: URL(fileURLWithPath: "/Projects/References", isDirectory: true))
        #expect(ShelfItemAppearance(item: link).subtitle == "You · Link · /reference")
        #expect(ShelfItemAppearance(item: text).subtitle == "You · 3 characters")
        #expect(ShelfItemAppearance(item: folder).subtitle == "You · Folder · Projects")
    }

    @Test func distinguishesLinksOnTheSameWebsite() {
        let first = ShelfItem(kind: .link, title: "example.com", detail: "", url: URL(string: "https://example.com/first"))
        let second = ShelfItem(kind: .link, title: "example.com", detail: "", url: URL(string: "https://example.com/second"))
        #expect(ShelfItemAppearance(item: first).subtitle != ShelfItemAppearance(item: second).subtitle)
    }
    @Test func showsTheAgentAndItsShortExplanation() {
        let item = ShelfItem(kind: .text, title: "Draft", detail: "", text: "Full content", source: "codex", note: "Revised introduction")
        let appearance = ShelfItemAppearance(item: item)
        #expect(appearance.subtitle == "Codex · Revised introduction")
        #expect(appearance.help.contains("12 characters"))
    }

    @Test(arguments: [
        ("human", "You"),
        ("codex", "Codex"),
        ("claude", "Claude Code"),
        ("grokbot", "Grokbot"),
        ("Research Bot", "Research Bot"),
        ("調査アシスタント", "調査アシスタント")
    ])
    func showsWhoAddedTheItem(source: String, displayName: String) {
        let item = ShelfItem(kind: .text, title: "Draft", detail: "", text: "Content", source: source)
        let appearance = ShelfItemAppearance(item: item)
        #expect(appearance.subtitle == "\(displayName) · 7 characters")
        #expect(appearance.help.hasPrefix("\(displayName) · "))
        if source != "human" {
            #expect(!appearance.subtitle.hasPrefix("You · "))
        }
    }

}
