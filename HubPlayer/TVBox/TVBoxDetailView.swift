import SwiftUI

/// 详情页：海报 + 元信息 + 线路/选集 + 收藏 + 播放
struct TVBoxDetailView: View {
    @ObservedObject var store: TVBoxStore
    let vod: VodItem
    @EnvironmentObject var player: PlayerManager
    @State private var groupIndex = 0
    @State private var playError: String?
    @State private var isResolving = false
    @State private var showInfo = false

    private var item: VodItem { store.detail ?? vod }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if store.isLoadingDetail { ProgressView().frame(maxWidth: .infinity) }
                if let e = store.detailError {
                    Label(e, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !item.playFrom.isEmpty { episodes }
                if !item.content.isEmpty { description }
            }
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let r = WatchRecord(siteKey: store.currentSite?.key ?? "",
                                        siteName: store.currentSite?.name ?? "",
                                        vodId: item.id, vodName: item.name, pic: item.pic,
                                        remarks: item.remarks, lastEpisode: "",
                                        date: Date().timeIntervalSince1970)
                    store.library.toggleFavorite(r)
                } label: {
                    Image(systemName: store.library.isFavorite((store.currentSite?.key ?? "") + "|" + item.id)
                          ? "heart.fill" : "heart")
                }
            }
        }
        .task { await store.loadDetail(id: vod.id, fallback: vod) }
        .alert("播放失败", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
            Button("好") { playError = nil }
        } message: { Text(playError ?? "") }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: item.pic)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Rectangle().fill(.quaternary).overlay(Image(systemName: "film"))
                }
            }
            .frame(width: 108, height: 152)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.headline).lineLimit(3)
                meta("年份", item.year)
                meta("地区", item.area)
                meta("类型", item.typeName)
                meta("导演", item.director)
                meta("主演", item.actor)
                if !item.remarks.isEmpty { meta("状态", item.remarks) }
                Spacer(minLength: 0)
            }
            .font(.caption)
        }
    }

    private func meta(_ k: String, _ v: String) -> some View {
        Group {
            if !v.isEmpty {
                HStack(alignment: .top) {
                    Text(k + "：").foregroundStyle(.tertiary)
                    Text(v).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 线路
            if item.playFrom.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(item.playFrom.enumerated()), id: \.offset) { idx, name in
                            Button(name) { groupIndex = idx }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(groupIndex == idx ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08),
                                            in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            let eps = groupIndex < item.playGroups.count ? item.playGroups[groupIndex] : []
            if eps.isEmpty {
                Text("该线路暂无选集").font(.caption).foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                    ForEach(eps) { ep in
                        Button {
                            Task { await play(ep: ep) }
                        } label: {
                            Text(ep.name)
                                .font(.caption).lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolving)
                    }
                }
            }
            if isResolving {
                HStack(spacing: 8) { ProgressView(); Text("正在解析播放地址…").font(.caption) }
            }
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showInfo.toggle()
            } label: {
                Label("简介", systemImage: showInfo ? "chevron.up" : "chevron.down").font(.subheadline)
            }.buttonStyle(.plain)
            if showInfo {
                Text(item.content).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func play(ep: VodEpisode) async {
        guard let site = store.currentSite else { return }
        guard !ep.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            playError = "选集「\(ep.name)」没有播放地址，请换线路或换源"
            return
        }
        isResolving = true
        defer { isResolving = false }
        do {
            let flag = groupIndex < item.playFrom.count ? item.playFrom[groupIndex] : ""
            let (url, headers, _) = try await store.resolvePlay(site: site, flag: flag, value: ep.value)
            store.record(vod: item, episode: ep.name, site: site)
            player.play(url, title: "\(item.name) · \(ep.name)", headers: headers)
        } catch {
            playError = error.localizedDescription
        }
    }
}
