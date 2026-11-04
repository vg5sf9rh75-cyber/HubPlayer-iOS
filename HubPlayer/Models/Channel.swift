import Foundation

struct Channel: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: URL
    let group: String
    let logo: URL?
}
