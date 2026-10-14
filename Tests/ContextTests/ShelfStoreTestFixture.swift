import ContextCore
import Foundation
import Testing
@testable import Context

@MainActor
final class ShelfStoreTestFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ContextShelfTests-\(UUID().uuidString)", isDirectory: true)

    var repository: ContextRepository { ContextRepository(rootURL: rootURL) }

    func makeStore(errorPresenter: @escaping @MainActor (Error) -> Void = { error in
        Issue.record("Unexpected shelf error: \(error)")
    }) -> ShelfStore {
        ShelfStore(repository: repository, errorPresenter: errorPresenter)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
