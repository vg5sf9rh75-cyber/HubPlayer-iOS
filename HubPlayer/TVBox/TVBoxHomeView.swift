import SwiftUI

/// 首页：对齐 Hub 安卓端「首页」——站点切换 + 分类 + 筛选 + 影片墙
struct TVBoxHomeView: View {
    @ObservedObject var store: TVBoxStore
    @State private var showSitePicker = false
    @State private var siteQuery = ""

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoadingConfig {
                    ProgressView("正在加载配置…")
                } else if let err = store.configError {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.orange)
                        Text("配置加载失败").font(.headline)
                        Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("重试") { Task { await store.loadConfig(force: true) } }
                            .buttonStyle(.borderedProminent)
                        Text("到「设置」填写配置地址，或添加自定义站点")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }.padding()
                } else if store.sites.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2").font(.largeTitle)
                        Text("暂无站点").font(.headline)
                        Text("在「设置」填写配置地址、粘贴配置，或添加自定义站点").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    content
                }
            }
            .navigationTitle(store.currentSite?.name ?? "Hub 播放器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSitePicker = true
                    } label: {
                        Label("切换源", systemImage: "square.stack.3d.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await store.loadSite(store.currentSite ?? store.sites[0]) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showSitePicker) { sitePicker }
            .task { await store.loadConfig() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 分类
                if !store.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryChip("全部", tid: "")
                            ForEach(store.categories) { c in
                                categoryChip(c.name, tid: c.id)
                            }
                        }.padding(.horizontal)
                    }
                }
                // 筛选
                if !store.filters.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.filters) { f in
                                Menu {
                                    ForEach(f.options) { o in
                                        Button {
                                            Task { await store.applyFilter(key: f.key, value: o.v) }
                                        } label: {
                                            if store.activeFilters[f.key] == o.v {
                                                Label(o.n, systemImage: "checkmark")
                                            } else { Text(o.n) }
                                        }
                                    }
                                } label: {
                                    let cur = f.options.first { store.activeFilters[f.key] == $0.v }?.n ?? f.name
                                    HStack(spacing: 4) {
                                        Text(cur).font(.caption)
                                        Image(systemName: "chevron.down").font(.caption2)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.thinMaterial, in: Capsule())
                                }
                            }
                        }.padding(.horizontal)
                    }
                }

                if let err = store.error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(err).font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal)
                }

                if store.vods.isEmpty && !store.isLoading {
                    ContentUnavailableFallback(title: "暂无内容",
                                               subtitle: "csp_ 是安卓 DEX 插件，单机版无法执行。到「设置」添加 CMS / JSON 站点，或载入演示站点验证播放链路")
                        .frame(minHeight: 240)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.vods) { vod in
                            NavigationLink(value: vod) {
                                VodCard(vod: vod)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if vod.id == store.vods.last?.id { Task { await store.loadMore() } }
                            }
                        }
                    }
                    .padding(.horizontal)

                    if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                    if store.page < store.pageCount {
                        Button("加载更多（第 \(store.page)/\(store.pageCount) 页）") {
                            Task { await store.loadMore() }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await store.loadSite(store.currentSite ?? store.sites[0]) }
        .navigationDestination(for: VodItem.self) { vod in
            TVBoxDetailView(store: store, vod: vod)
        }
    }

    private func categoryChip(_ name: String, tid: String) -> some View {
        Button {
            Task {
                if tid.isEmpty {
                    await store.loadSite(store.currentSite ?? store.sites[0])
                } else {
                    await store.selectCategory(tid)
                }
            }
        } label: {
            Text(name).font(.subheadline).fontWeight(store.selectedTid == tid ? .semibold : .regular)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(store.selectedTid == tid ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var sitePicker: some View {
        NavigationStack {
            List {
                ForEach(siteQuery.isEmpty ? store.sites : store.sites.filter {
                    $0.name.localizedCaseInsensitiveContains(siteQuery) || $0.key.localizedCaseInsensitiveContains(siteQuery)
                }) { site in
                    Button {
                        showSitePicker = false
                        Task { await store.loadSite(site) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(site.name).font(.subheadline)
                                Text(site.api).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                            if site.isCsp {
                                Text("需安卓 DEX · 不可点播")
                                    .font(.caption2).foregroundStyle(.orange)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                            if site.key == store.currentSite?.key {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
            .searchable(text: $siteQuery, prompt: "搜索站点（共 \(store.sites.count) 个）")
            .navigationTitle("切换站点")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showSitePicker = false }
                }
            }
        }
    }
}

struct VodCard: View {
    let vod: VodItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: vod.pic)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                    }
                }
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !vod.remarks.isEmpty {
                    Text(vod.remarks)
                        .font(.caption2).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3))
                        .padding(5)
                }
            }
            Text(vod.name).font(.caption).lineLimit(2)
            if !vod.year.isEmpty || !vod.typeName.isEmpty {
                Text([vod.typeName, vod.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}
