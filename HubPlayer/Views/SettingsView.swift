import SwiftUI

struct SettingsView: View {
    @State private var newSource = ""
    @State private var sources: [String] = SourceStore.shared.sources

    var body: some View {
        NavigationStack {
            Form {
                Section("添加直播源 (M3U / M3U8 订阅地址)") {
                    TextField("https://.../playlist.m3u", text: $newSource)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("添加") {
                        SourceStore.shared.add(newSource)
                        sources = SourceStore.shared.sources
                        newSource = ""
                    }
                }
                Section("已保存的源") {
                    ForEach(sources, id: \.self) { s in
                        Text(s).font(.footnote)
                    }
                    .onDelete { offsets in
                        for i in offsets { SourceStore.shared.remove(sources[i]) }
                        sources = SourceStore.shared.sources
                    }
                }
                Section("关于") {
                    Text("Hub 播放器 iOS 版 · 用于播放 M3U 直播源与 WebDAV 网盘视频。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
