import Foundation

enum ContextDeepLink: Equatable {
    case shelf
    case clipboard
    case settings
    case item(UUID)

    init?(url: URL) {
        guard url.scheme == "context",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }

        switch url.host {
        case "shelf" where url.path.isEmpty || url.path == "/": self = .shelf
        case "clipboard" where url.path.isEmpty || url.path == "/": self = .clipboard
        case "settings" where url.path.isEmpty || url.path == "/": self = .settings
        case "item":
            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count == 1, let id = UUID(uuidString: components[0]) else { return nil }
            self = .item(id)
        default: return nil
        }
    }
}
