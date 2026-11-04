import SwiftUI

struct QuarkFolder: Hashable {
    let fid: String
    let name: String
}

struct QuarkView: View {
    @AppStorage("quarkCookie") private var cookie = ""

    @State private var showLogin = false
    @State private var items: [QuarkFile] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    @EnvironmentObject private var manager: PlayerManager

    var body: some View {
        NavigationStack {
            Group {
                if cookie.isEmpty {
                    ContentUnavailableFallback(title: "未登录夸克网盘",
                                              subtitle: "在下方粘贴浏览器里的 kpsid / Cookie 后点“保存并连接”")
                } else {
                    List {
                        if isLoading { ProgressView("加载中…") }
                        if let errorMsg { Text(errorMsg).foregroundColor(.red) }
                        ForEach(items) { file in
                            if file.isDir {
                                NavigationLink(value: QuarkFolder(fid: file.fid, name: file.name)) {
                                    Label(file.name, systemImage: "folder")
                                }
                            } else {
                                Button { play(file) } label: {
                                    HStack {
                                        Label(file.name, systemImage: "play.circle")
                                        Spacer()
                                        if !file.sizeText.isEmpty {
                                            Text(file.sizeText)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("网盘 (夸克)")
            .navigationDestination(for: QuarkFolder.self) { folder in
                QuarkFolderView(folder: folder)
                    .environmentObject(manager)
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("刷新") { Task { await load(fid: QuarkManager.rootFid) } }
                        .disabled(cookie.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                configBar
            }
        }
        .onAppear { if !cookie.isEmpty { Task { await load(fid: QuarkManager.rootFid) } } }
        .sheet(isPresented: $showLogin) {
            LoginWebView(
                title: "夸克扫码登录",
                loginURL: URL(string: "https://pan.quark.cn/")!,
                cookieDomain: "pan.quark.cn",
                storageKey: "quarkCookie"
            )
        }
    }

    private var configBar: some View {
        VStack(spacing: 6) {
            TextField("粘贴夸克 Cookie（kpsid=... 或整段）", text: $cookie)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("保存并连接") {
                    Task { await load(fid: QuarkManager.rootFid) }
                }
                Button("扫码登录") { showLogin = true }
                Spacer()
                let query = "夸克网盘 kpsid cookie".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let helpURL = URL(string: "https://www.baidu.com/s?wd=\(query)") ?? URL(string: "https://www.baidu.com")!
                Link("如何获取?", destination: helpURL)
            }
        }
        .padding(8)
        .background(.bar)
    }

    func load(fid: String) async {
        isLoading = true
        errorMsg = nil
        do {
            let result = try await QuarkManager.shared.list(pdirFid: fid, cookie: cookie)
            await MainActor.run {
                self.items = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMsg = "加载失败：\(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func play(_ file: QuarkFile) {
        guard !cookie.isEmpty else { return }
        Task {
            do {
                let (urlStr, name) = try await QuarkManager.shared.getDownloadURL(fid: file.fid, cookie: cookie)
                guard let url = URL(string: urlStr) else { throw QuarkError.message("直链不是合法 URL") }
                let headers = [
                    "Referer": "https://pan.quark.cn/",
                    "Cookie": cookie,
                ]
                await MainActor.run {
                    manager.play(url, title: name, headers: headers)
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = "获取直链失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

struct QuarkFolderView: View {
    let folder: QuarkFolder
    @AppStorage("quarkCookie") private var cookie = ""

    @State private var items: [QuarkFile] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    @EnvironmentObject private var manager: PlayerManager

    var body: some View {
        Group {
            if isLoading { ProgressView("加载中…") }
            if let errorMsg { Text(errorMsg).foregroundColor(.red) }
            List {
                ForEach(items) { file in
                    if file.isDir {
                        NavigationLink(value: QuarkFolder(fid: file.fid, name: file.name)) {
                            Label(file.name, systemImage: "folder")
                        }
                    } else {
                        Button { play(file) } label: {
                            HStack {
                                Label(file.name, systemImage: "play.circle")
                                Spacer()
                                if !file.sizeText.isEmpty {
                                    Text(file.sizeText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .task { await load() }
    }

    func load() async {
        isLoading = true
        errorMsg = nil
        do {
            let result = try await QuarkManager.shared.list(pdirFid: folder.fid, cookie: cookie)
            await MainActor.run {
                self.items = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMsg = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func play(_ file: QuarkFile) {
        guard !cookie.isEmpty else { return }
        Task {
            do {
                let (urlStr, name) = try await QuarkManager.shared.getDownloadURL(fid: file.fid, cookie: cookie)
                guard let url = URL(string: urlStr) else { throw QuarkError.message("直链不是合法 URL") }
                let headers = [
                    "Referer": "https://pan.quark.cn/",
                    "Cookie": cookie,
                ]
                await MainActor.run {
                    manager.play(url, title: name, headers: headers)
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = "获取直链失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
