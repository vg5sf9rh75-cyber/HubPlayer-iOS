import Foundation

final class SourceStore {
    static let shared = SourceStore()
    private let key = "liveSources"

    var sources: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func add(_ url: String) {
        let t = url.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !sources.contains(t) else { return }
        sources = sources + [t]
    }

    func remove(_ url: String) {
        sources = sources.filter { $0 != url }
    }
}
