import Foundation

public enum CCSource {
    public static func isValid(_ source: String) -> Bool {
        guard !source.isEmpty,
              source.count <= 64,
              source.utf8.count <= 256,
              source.trimmingCharacters(in: .whitespacesAndNewlines) == source else {
            return false
        }
        let excluded = CharacterSet.controlCharacters.union(.newlines)
        return source.unicodeScalars.allSatisfy { !excluded.contains($0) }
    }

    public static func displayName(for source: String) -> String {
        switch source {
        case "human": "You"
        case "codex": "Codex"
        case "claude": "Claude Code"
        case "antigravity": "Antigravity"
        case "grokbot": "Grokbot"
        default: source
        }
    }
}
