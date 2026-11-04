import SwiftUI

struct NetworkView: View {
    @State private var urlText = ""
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentUrls") ?? []

    @EnvironmentObject private var manager: PlayerManager

    var body: some View {
        NavigationStack {
            Form {
                Section("直接播放链接") {
                    TextField("http(s):// 视频地址", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("播放") { play() }
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("最近播放") {
                    ForEach(recent, id: \.self) { u in
                        Button { urlText = u; play() } label: { Text(u).lineLimit(1) }
                    }
                    if !recent.isEmpty {
                        Button("清空", role: .destructive) {
                            recent.removeAll()
                            UserDefaults.standard.set([], forKey: "recentUrls")
                        }
                    }
                }
            }
            .navigationTitle("网络视频")
        }
    }

    func play() {
        let t = urlText.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t) else { return }
        if !recent.contains(t) {
            recent.insert(t, at: 0)
            UserDefaults.standard.set(recent, forKey: "recentUrls")
        }
        manager.play(u, title: t)
    }
}
