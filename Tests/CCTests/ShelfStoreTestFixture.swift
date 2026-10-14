import CCCore
import Foundation
import Testing
@testable import CC

@MainActor
final class ShelfStoreTestFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CCShelfTests-\(UUID().uuidString)", isDirectory: true)

    var repository: CCRepository { CCRepository(rootURL: rootURL) }

    func makeStore(errorPresenter: @escaping @MainActor (Error) -> Void = { error in
        Issue.record("Unexpected shelf error: \(error)")
    }) -> ShelfStore {
        ShelfStore(repository: repository, errorPresenter: errorPresenter)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
