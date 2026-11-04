import SwiftUI

struct LiveView: View {
    @State private var channels: [Channel] = []
    @State private var groups: [String: [Channel]] = [:]
    @State private var selectedSource: String = ""
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var searchText = ""

    @EnvironmentObject private var manager: PlayerManager

    private var sources: [String] { SourceStore.shared.sources }

    private var filteredGroups: [(String, [Channel])] {
        let all = groups.sorted { $0.key < $1.key }
        if searchText.isEmpty { return all }
        return all
            .map { ($0.key, $0.value.filter { $0.title.localizedCaseInsensitiveContains(searchText) }) }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if sources.isEmpty {
                    ContentUnavailableFallback(title: "还没有直播源",
                                              subtitle: "去“设置”里添加 M3U / M3U8 订阅地址")
                } else {
                    Picker("选择源", selection: $selectedSource) {
                        ForEach(sources, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedSource) { _ in load() }

                    if isLoading { ProgressView("加载中…") }
                    if let errorMsg {
                        Text(errorMsg).foregroundColor(.red).padding()
                    }

                    List {
                        ForEach(filteredGroups, id: \.0) { group, chs in
                            Section(group) {
                                ForEach(chs) { ch in
                                    Button {
                                        manager.play(ch.url, title: ch.title)
                                    } label: {
                                        HStack(spacing: 12) {
                                            if let logo = ch.logo {
                                                AsyncImage(url: logo) { image in
                                                    image.resizable()
                                                } placeholder: {
                                                    Color.gray
                                                }
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(4)
                                            }
                                            Text(ch.title).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText)
                }
            }
            .navigationTitle("直播源")
            .onAppear {
                if selectedSource.isEmpty, !sources.isEmpty {
                    selectedSource = sources[0]
                }
            }
        }
    }

    func load() {
        guard !selectedSource.isEmpty else { return }
        isLoading = true
        errorMsg = nil
        Task {
            do {
                let chs = try await PlaylistParser.fetch(from: selectedSource)
                let grouped = Dictionary(grouping: chs) { $0.group }
                await MainActor.run {
                    self.channels = chs
                    self.groups = grouped
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = "加载失败：\(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

/// iOS 16 兼容的占位视图（ContentUnavailableView 仅 iOS 17+）
struct ContentUnavailableFallback: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv").font(.largeTitle)
            Text(title).font(.headline)
            Text(subtitle).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
