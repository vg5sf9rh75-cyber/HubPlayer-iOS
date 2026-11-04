import SwiftUI

// MARK: - 搜索页（支持当前源 / 全站聚合搜索）

struct TVBoxSearchView: View {
    @ObservedObject var store: TVBoxStore
    @State private var hotSites: [TVBoxSite] = []

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Toggle("全站聚合搜索（\(store.sites.filter { ($0.searchable ?? 1) == 1 && !$0.isCsp }.count) 个可直连源）",
                       isOn: $store.searchScopeAll)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                if !store.searchProgress.isEmpty {
                    Text(store.searchProgress).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }

                if store.isSearching {
                    ProgressView("搜索中…").frame(maxWidth: .infinity, minHeight: 120)
                } else if store.searchResults.isEmpty {
                    ContentUnavailableFallback(title: "搜索影片",
                                               subtitle: "输入关键词，可切换「全站聚合搜索」一次搜遍所有站点")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.searchResults) { vod in
                                NavigationLink(value: vod) { VodCard(vod: vod) }
                                    .buttonStyle(.plain)
                            }
                        }.padding()
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $store.searchText, prompt: "影片名 / 演员")
            .onSubmit(of: .search) { Task { await store.search() } }
            .navigationDestination(for: VodItem.self) { vod in
                TVBoxDetailView(store: store, vod: vod)
            }
        }
    }
}

// MARK: - 直播页（分组 + EPG + 屏显信息）

struct TVBoxLiveView: View {
    @ObservedObject var store: TVBoxStore
    @EnvironmentObject var player: PlayerManager
    @State private var selectedGroup: String = "全部"
    @State private var query = ""
    @State private var playError: String?

    private var visible: [M3UChannel] {
        store.channels.filter { ch in
            (selectedGroup == "全部" || ch.group == selectedGroup) &&
            (query.isEmpty || ch.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 直播源切换
                if !store.liveSources.isEmpty { liveSourceBar }
                // 分组
                if !store.liveGroups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            groupChip("全部")
                            ForEach(store.liveGroups, id: \.self) { groupChip($0) }
                        }.padding(.horizontal)
                    }.padding(.bottom, 6)
                }

                if store.isLoadingLive { ProgressView().padding() }

                if visible.isEmpty {
                    ContentUnavailableFallback(title: "暂无频道",
                                               subtitle: "到「设置」添加直播源或粘贴 M3U 文本")
                        .frame(maxHeight: .infinity)
                } else {
                    List(visible) { ch in
                        Button {
                            let (url, headers) = store.livePlay(ch)
                            guard let url else { playError = "频道地址无效"; return }
                            player.play(url, title: ch.name, headers: headers)
                        } label: {
                            HStack(spacing: 10) {
                                AsyncImage(url: URL(string: ch.logo)) { p in
                                    if case .success(let img) = p { img.resizable().scaledToFit() }
                                    else { Image(systemName: "tv").foregroundStyle(.secondary) }
                                }.frame(width: 34, height: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ch.name).font(.subheadline).lineLimit(1)
                                    if store.showVideoInfo {
                                        Text(ch.group + " · " + shortURL(ch.url))
                                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle").foregroundStyle(.tint)
                            }
                        }.buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("直播")
            .searchable(text: $query, prompt: "搜索频道")
            .task {
                if let first = store.liveSources.first, store.channels.isEmpty {
                    await store.loadLive(first)
                }
            }
            .alert("播放失败", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
                Button("好") { playError = nil }
            } message: { Text(playError ?? "") }
        }
    }

    private var liveSourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.liveSources) { src in
                    liveSourceButton(src)
                }
            }.padding(.horizontal)
        }.padding(.vertical, 6)
    }

    private func liveSourceButton(_ src: TVBoxLive) -> some View {
        let selected = store.selectedLive?.id == src.id
        let fill: Color = selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08)
        return Button(src.name) { Task { await store.loadLive(src) } }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(fill, in: Capsule())
            .buttonStyle(.plain)
    }

    private func groupChip(_ name: String) -> some View {
        Button(name) { selectedGroup = name }
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selectedGroup == name ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08),
                        in: Capsule())
            .buttonStyle(.plain)
    }

    private func shortURL(_ s: String) -> String {
        guard let u = URL(string: s) else { return s }
        return (u.host ?? "") + u.path
    }
}

// MARK: - 我的（历史 / 收藏 / 原有功能入口）

struct TVBoxLibraryView: View {
    @ObservedObject var store: TVBoxStore
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $tab) {
                    Text("播放历史").tag(0)
                    Text("我的收藏").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())

                let items = tab == 0 ? store.library.history : store.library.favorites
                if items.isEmpty {
                    Text(tab == 0 ? "暂无播放记录" : "暂无收藏")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(items) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.vodName).font(.subheadline)
                            Text(r.siteName + (r.lastEpisode.isEmpty ? "" : " · " + r.lastEpisode))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("更多功能") {
                    NavigationLink("网络直链") { NetworkView() }
                    NavigationLink("网盘 WebDAV") { WebDavView() }
                    NavigationLink("夸克网盘") { QuarkView() }
                    NavigationLink("哔哩哔哩") { BiliView() }
                }
            }
            .navigationTitle("我的")
        }
    }
}

// MARK: - 设置（单机本地引擎 / 后期自行配置）

struct TVBoxSettingsView: View {
    @ObservedObject var store: TVBoxStore
    @State private var configURL: String = RelayClient.shared.configURL
    @State private var pastedConfig: String = RelayClient.shared.pastedConfig
    @State private var pastedM3U: String = RelayClient.shared.pastedM3U
    @State private var customSites: [[String: String]] = RelayClient.shared.customSites
    @State private var customLives: [[String: String]] = RelayClient.shared.customLives
    @State private var status: String = ""
    @State private var showInfo: Bool = UserDefaults.standard.bool(forKey: "tvbox.showVideoInfo")
    @State private var showAddSite = false
    @State private var showAddLive = false

    var body: some View {
        NavigationStack {
            Form {
                Section("运行方式") {
                    LabeledContent("模式", value: "单机本地引擎")
                    Text("不需要第二台设备。csp_ 站点是安卓 DEX 插件（依赖 Dalvik + ARM .so），iOS 无法执行，只能保留为占位；点播请填苹果CMS v10 / 返回 {list:[...]} 的 JSON 接口，或粘贴 M3U 直链。")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Button("载入演示站点（验证播放链路）") {
                        if !customSites.contains(where: { $0["api"] == "hub://demo" }) {
                            customSites.append([
                                "key": "demo_local",
                                "name": "演示站点（可删）",
                                "type": "0",
                                "api": "hub://demo",
                                "ext": ""
                            ])
                        }
                        save()
                        store.config = nil
                        store.currentSite = nil
                        status = "已载入演示站点：首页点海报 → 选集 → 应出现测试画面"
                        Task { await store.loadConfig(force: true) }
                    }
                    Button("自检并重新加载") {
                        save()
                        Task {
                            do {
                                let d = try await RelayClient.shared.ping()
                                let sites = d["sites"] as? Int ?? 0
                                let usable = d["usable"] as? Int ?? 0
                                let lives = d["lives"] as? Int ?? 0
                                status = "本地引擎就绪｜站点 \(sites) 个（可直连 \(usable)）｜直播源 \(lives) 个"
                                store.config = nil
                                await store.loadConfig(force: true)
                            } catch {
                                status = "自检失败：" + error.localizedDescription
                            }
                        }
                    }
                    if !status.isEmpty {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("配置来源") {
                    TextField("配置地址（可留空）", text: $configURL)
                        .keyboardType(.URL).autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("或直接粘贴配置内容（JSON / base64），优先级高于地址")
                        .font(.caption2).foregroundStyle(.tertiary)
                    TextEditor(text: $pastedConfig)
                        .frame(minHeight: 96)
                        .font(.system(.caption2, design: .monospaced))
                    Button("保存配置并重载") {
                        save()
                        store.config = nil
                        Task { await store.loadConfig(force: true) }
                    }
                    if let cfg = store.config {
                        LabeledContent("站点", value: "\(cfg.sites.count) 个")
                        LabeledContent("其中可直连", value: "\(cfg.sites.filter { !$0.isCsp }.count) 个")
                        LabeledContent("直播源", value: "\(cfg.lives.count) 个")
                    }
                }

                Section {
                    ForEach(customSites.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customSites[i]["name"] ?? "自定义站点").font(.subheadline)
                            Text(customSites[i]["api"] ?? "")
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    .onDelete { idx in
                        for i in idx.sorted(by: >) { customSites.remove(at: i) }
                        RelayClient.shared.customSites = customSites
                    }
                    Button("添加站点") { showAddSite = true }
                } header: {
                    Text("自定义站点（\(customSites.count)）")
                } footer: {
                    Text("填 CMS / 苹果CMS v10 采集地址，例如 https://example.com/api.php/provide/vod/ ，或任意返回 {list:[...]} 的直链。")
                        .font(.caption2)
                }

                Section {
                    ForEach(customLives.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customLives[i]["name"] ?? "自定义直播").font(.subheadline)
                            Text(customLives[i]["url"] ?? "")
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    .onDelete { idx in
                        for i in idx.sorted(by: >) { customLives.remove(at: i) }
                        RelayClient.shared.customLives = customLives
                    }
                    Button("添加直播源（M3U 地址）") { showAddLive = true }
                    Text("或直接粘贴 M3U 文本，会生成「粘贴的直播源」")
                        .font(.caption2).foregroundStyle(.tertiary)
                    TextEditor(text: $pastedM3U)
                        .frame(minHeight: 80)
                        .font(.system(.caption2, design: .monospaced))
                    Button("保存全部设置") {
                        save()
                        store.config = nil
                        Task { await store.loadConfig(force: true) }
                    }
                } header: {
                    Text("直播源（\(customLives.count) 自定义）")
                }

                Section("播放与显示") {
                    Toggle("播放时显示详细信息（分组 / 地址）", isOn: $showInfo)
                        .onChange(of: showInfo) { store.setShowVideoInfo($0) }
                    Text("对应安卓端「个性设置 → 屏显」的详细信息开关。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Section("状态") {
                    if let cfg = store.config, cfg.sites.filter({ !$0.isCsp }).isEmpty {
                        Text("⚠️ 当前 \(cfg.sites.count) 个站点全是 csp_ 安卓 DEX 插件，没有可点播的源。请添加 CMS / JSON 站点，或载入演示站点。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let err = store.configError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    } else if store.config != nil {
                        Text("配置已加载（本地）").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("尚未加载配置").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showAddSite) {
                AddSiteView { item in
                    customSites.append(item)
                    RelayClient.shared.customSites = customSites
                }
            }
            .sheet(isPresented: $showAddLive) {
                AddLiveView { item in
                    customLives.append(item)
                    RelayClient.shared.customLives = customLives
                }
            }
        }
    }

    private func save() {
        RelayClient.shared.configURL = configURL
        RelayClient.shared.pastedConfig = pastedConfig
        RelayClient.shared.pastedM3U = pastedM3U
        RelayClient.shared.customSites = customSites
        RelayClient.shared.customLives = customLives
        RelayClient.shared.baseURL = ""
    }
}

// MARK: - 添加自定义站点 / 直播源

struct AddSiteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var api = ""
    @State private var ext = ""
    @State private var type = "0"
    let onAdd: ([String: String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("站点名称", text: $name)
                    TextField("API 地址", text: $api)
                        .keyboardType(.URL).autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("ext（可选，规则或直链）", text: $ext)
                        .autocapitalization(.none).disableAutocorrection(true)
                }
                Section("类型") {
                    Picker("站点类型", selection: $type) {
                        Text("0 · CMS / 直链 JSON").tag("0")
                        Text("1 · 采集规则").tag("1")
                        Text("3 · 仅占位（csp）").tag("3")
                    }
                }
                Section {
                    Text("引擎把 homeContent / categoryContent / detailContent / searchContent 映射到标准苹果CMS 参数（ac=videolist、t、pg、wd、ids）。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("添加站点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let value = api.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        onAdd([
                            "key": "custom_\(Int(Date().timeIntervalSince1970))",
                            "name": name.isEmpty ? "自定义站点" : name,
                            "type": type,
                            "api": value,
                            "ext": ext
                        ])
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddLiveView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    let onAdd: ([String: String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("M3U / M3U8 地址", text: $url)
                    .keyboardType(.URL).autocapitalization(.none)
                    .disableAutocorrection(true)
                Text("也支持 txt / php 代理接口，只要返回标准 M3U 文本。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .navigationTitle("添加直播源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        onAdd(["name": name.isEmpty ? "自定义直播" : name, "url": value])
                        dismiss()
                    }
                }
            }
        }
    }
}
