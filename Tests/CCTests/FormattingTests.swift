import Testing
@testable import CC

struct FormattingTests {
    @Test(arguments: [".", ".."])
    func replacesSpecialDirectorySegmentsWithTheFallbackName(input: String) {
        #expect(input.sanitizedFileName(defaultName: "Item") == "Item")
    }

    @Test func choosesTheSecondaryActionFromTheItemKind() {
        let link = ShelfItem(kind: .link, title: "Example", detail: "https://example.com")
        let file = ShelfItem(kind: .file, title: "notes.txt", detail: "/tmp")

        #expect(link.secondaryAction == .copy)
        #expect(file.secondaryAction == .reveal)
    }
}
