import Foundation
import SwiftUI

/// 播放历史 / 收藏（本地持久化）
struct WatchRecord: Codable, Identifiable, Hashable {
    var id: String { siteKey + "|" + vodId }
    var siteKey: String
    var siteName: String
    var vodId: String
    var vodName: String
    var pic: String
    var remarks: String
    var lastEpisode: String
    var date: Double
}

final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published var history: [WatchRecord] = []
    @Published var favorites: [WatchRecord] = []

    private let hKey = "tvbox.history"
    private let fKey = "tvbox.favorites"

    init() {
        history = load(hKey)
        favorites = load(fKey)
    }

    func addHistory(_ r: WatchRecord) {
        history.removeAll { $0.id == r.id }
        history.insert(r, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        save(history, hKey)
    }

    func toggleFavorite(_ r: WatchRecord) {
        if let i = favorites.firstIndex(where: { $0.id == r.id }) {
            favorites.remove(at: i)
        } else {
            favorites.insert(r, at: 0)
        }
        save(favorites, fKey)
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains { $0.id == id } }

    private func load(_ key: String) -> [WatchRecord] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let a = try? JSONDecoder().decode([WatchRecord].self, from: d) else { return [] }
        return a
    }
    private func save(_ a: [WatchRecord], _ key: String) {
        guard let d = try? JSONEncoder().encode(a) else { return }
        UserDefaults.standard.set(d, forKey: key)
    }
}

/// 首页 / 分类 / 搜索 / 详情 的状态机
@MainActor
final class TVBoxStore: ObservableObject {
    @Published var config: TVBoxConfig?
    @Published var configError: String?
    @Published var isLoadingConfig = false

    @Published var currentSite: TVBoxSite?
    @Published var categories: [VodCategory] = []
    @Published var selectedTid: String = ""
    @Published var page: Int = 1
    @Published var pageCount: Int = 1
    @Published var vods: [VodItem] = []
    @Published var filters: [VodFilter] = []
    @Published var activeFilters: [String: String] = [:]
    @Published var isLoading = false
    @Published var error: String?

    @Published var searchText = ""
    @Published var searchResults: [VodItem] = []
    @Published var isSearching = false
    @Published var searchScopeAll = false      // 全站搜索
    @Published var searchProgress: String = ""

    @Published var detail: VodItem?
    @Published var isLoadingDetail = false
    @Published var detailError: String?

    @Published var liveSources: [TVBoxLive] = []
    @Published var channels: [M3UChannel] = []
    @Published var liveGroups: [String] = []
    @Published var selectedLive: TVBoxLive?
    @Published var isLoadingLive = false

    @Published var epgText: String = ""
    @Published var showVideoInfo = UserDefaults.standard.bool(forKey: "tvbox.showVideoInfo")

    let relay = RelayClient.shared
    let library = LibraryStore.shared

    var sites: [TVBoxSite] { config?.sites ?? [] }
    var parses: [TVBoxParse] { config?.parses ?? [] }

    /// 需要的自定义 Header（按 host 匹配），对齐配置 headers / rules
    func headers(for urlString: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let host = URL(string: urlString)?.host else { return out }
        for h in config?.headers ?? [] {
            if host.contains(h.host) || h.host.contains(host) {
                for (k, v) in h.header { out[k] = v }
            }
        }
        if let live = selectedLive, let ua = live.ua, !ua.isEmpty {
            out["User-Agent"] = ua
        }
        return out
    }

    // MARK: - 配置

    func loadConfig(force: Bool = false) async {
        if isLoadingConfig { return }
        if config != nil && !force { return }
        isLoadingConfig = true
        configError = nil
        defer { isLoadingConfig = false }
        do {
            let cfg = try await relay.fetchConfig()
            config = cfg
            liveSources = cfg.lives
            if currentSite == nil {
                currentSite = cfg.sites.first { !$0.isCsp } ?? cfg.sites.first
            }
            if let s = currentSite { await loadSite(s) }
        } catch {
            configError = error.localizedDescription
        }
    }

    // MARK: - 站点

    func loadSite(_ site: TVBoxSite) async {
        currentSite = site
        categories = []
        vods = []
        filters = []
        activeFilters = [:]
        selectedTid = ""
        page = 1
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await relay.homeContent(api: site.api, ext: site.ext?.text ?? "", filter: true)
            categories = p.categories
            vods = p.list
            pageCount = p.pageCount
            if let tid = p.categories.first?.id { filters = p.filters[tid] ?? [] }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectCategory(_ tid: String) async {
        guard let site = currentSite else { return }
        selectedTid = tid
        page = 1
        vods = []
        activeFilters = [:]
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await relay.categoryContent(api: site.api, ext: site.ext?.text ?? "",
                                                     tid: tid, page: 1, filter: true)
            vods = p.list
            pageCount = p.pageCount
            filters = p.filters[tid] ?? (tid.isEmpty ? [] : filters)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let site = currentSite, page < pageCount, !isLoading else { return }
        let next = page + 1
        isLoading = true
        defer { isLoading = false }
        do {
            let p: VodPage
            if selectedTid.isEmpty {
                p = try await relay.homeContent(api: site.api, ext: site.ext?.text ?? "", filter: true)
            } else {
                p = try await relay.categoryContent(api: site.api, ext: site.ext?.text ?? "",
                                                     tid: selectedTid, page: next,
                                                     filter: true, extend: activeFilters)
            }
            page = next
            let existing = Set(vods.map { $0.id })
            vods.append(contentsOf: p.list.filter { !existing.contains($0.id) })
            pageCount = p.pageCount
        } catch {
            self.error = error.localizedDescription
        }
    }

    func applyFilter(key: String, value: String) async {
        activeFilters[key] = value
        page = 1
        guard let site = currentSite else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await relay.categoryContent(api: site.api, ext: site.ext?.text ?? "",
                                                     tid: selectedTid, page: 1,
                                                     filter: true, extend: activeFilters)
            vods = p.list
            pageCount = p.pageCount
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - 搜索

    func search() async {
        let key = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isSearching = true
        searchResults = []
        searchProgress = ""
        defer { isSearching = false }

        if searchScopeAll {
            // 全站搜索：逐个站点并发（限 4 个），对齐安卓端「聚合搜索」
            let targets = sites.filter { ($0.searchable ?? 1) == 1 && !$0.isCsp }
            if targets.isEmpty {
                searchProgress = "没有可直连的站点，请先到「设置 → 自定义站点」添加 CMS / 直链接口"
                return
            }
            var all: [VodItem] = []
            let total = targets.count
            var done = 0
            await withTaskGroup(of: [VodItem].self) { group in
                var iterator = targets.makeIterator()
                for _ in 0..<min(4, targets.count) {
                    if let s = iterator.next() {
                        group.addTask { [relay] in
                            (try? await relay.searchContent(api: s.api, ext: s.ext?.text ?? "", key: key))?.list ?? []
                        }
                    }
                }
                for await res in group {
                    all.append(contentsOf: res)
                    done += 1
                    searchProgress = "已搜 \(done)/\(total) 个源，命中 \(all.count)"
                    if let s = iterator.next() {
                        group.addTask { [relay] in
                            (try? await relay.searchContent(api: s.api, ext: s.ext?.text ?? "", key: key))?.list ?? []
                        }
                    }
                }
            }
            searchResults = all
        } else {
            guard let site = currentSite else { return }
            do {
                let p = try await relay.searchContent(api: site.api, ext: site.ext?.text ?? "", key: key)
                searchResults = p.list
                if searchResults.isEmpty { searchProgress = "当前源无结果，可尝试「全站搜索」" }
            } catch {
                searchProgress = error.localizedDescription
            }
        }
    }

    // MARK: - 详情 / 播放

    func loadDetail(id: String, site: TVBoxSite? = nil) async {
        let s = site ?? currentSite
        guard let s else { return }
        isLoadingDetail = true
        detailError = nil
        defer { isLoadingDetail = false }
        do {
            detail = try await relay.detailContent(api: s.api, ext: s.ext?.text ?? "", id: id)
            if detail == nil { detailError = "该源未返回详情" }
        } catch { detailError = error.localizedDescription }
    }

    /// 解析选集为可播放地址：优先 playerContent，失败则用 parses 解析接口
    func resolvePlay(site: TVBoxSite, flag: String, value: String) async throws -> (URL, [String: String], String) {
        var result = try await relay.playerContent(api: site.api, ext: site.ext?.text ?? "",
                                                    flag: flag, id: value)
        var target = result.url.isEmpty ? value : result.url

        // parse=1 表示需要走解析接口
        if result.parse == 1 || result.jx == 1 || (!target.hasPrefix("http") && !target.contains("://")) {
            if let p = parses.first {
                target = try await relay.parse(parseURL: p.url, target: target)
            }
        }
        // 相对地址补全
        if !target.hasPrefix("http") && !target.contains("://"),
           let ext = site.ext?.text, let base = URL(string: ext), let u = URL(string: target, relativeTo: base) {
            target = u.absoluteString
        }
        guard let url = URL(string: target) else { throw RelayError.decode("播放地址无效：\(target)") }
        var h = result.headers
        for (k, v) in headers(for: target) where h[k] == nil { h[k] = v }
        result.url = target
        return (url, h, result.contentType)
    }

    func record(vod: VodItem, episode: String, site: TVBoxSite) {
        library.addHistory(WatchRecord(siteKey: site.key, siteName: site.name,
                                       vodId: vod.id, vodName: vod.name, pic: vod.pic,
                                       remarks: vod.remarks, lastEpisode: episode,
                                       date: Date().timeIntervalSince1970))
    }

    // MARK: - 直播

    func loadLive(_ live: TVBoxLive) async {
        selectedLive = live
        isLoadingLive = true
        defer { isLoadingLive = false }
        do {
            let text = try await relay.fetchText(live.url, ua: live.ua)
            channels = parseM3U(text, sourceName: live.name, defaultUA: live.ua)
            liveGroups = Array(Set(channels.map { $0.group })).sorted()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func livePlay(_ ch: M3UChannel) -> (URL?, [String: String]) {
        guard let url = URL(string: ch.url) else { return (nil, [:]) }
        var h = headers(for: ch.url)
        if let ua = ch.attrs["ua"], !ua.isEmpty { h["User-Agent"] = ua }
        return (url, h)
    }

    func setShowVideoInfo(_ on: Bool) {
        showVideoInfo = on
        UserDefaults.standard.set(on, forKey: "tvbox.showVideoInfo")
    }
}
