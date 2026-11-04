import SwiftUI

struct WebDavFolder: Hashable {
    let path: String
    let name: String
}

struct WebDavView: View {
    @AppStorage("webdavHost") private var host = ""
    @AppStorage("webdavUser") private var user = ""
    @AppStorage("webdavPass") private var pass = ""
    @State private var items: [WebDavItem] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    @EnvironmentObject private var manager: PlayerManager

    var body: some View {
        NavigationStack {
            Group {
                if host.isEmpty {
                    ContentUnavailableFallback(title: "未配置 WebDAV",
                                              subtitle: "在下方填写服务器地址后点“连接”")
                } else {
                    List {
                        if isLoading { ProgressView("加载中…") }
                        if let errorMsg { Text(errorMsg).foregroundColor(.red) }
                        ForEach(items) { item in
                            if item.isDirectory {
                                NavigationLink(value: WebDavFolder(path: item.path, name: item.name)) {
                                    Label(item.name, systemImage: "folder")
                                }
                            } else {
                                Button { play(item) } label: { Label(item.name, systemImage: "play.circle") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("网盘 (WebDAV)")
            .navigationDestination(for: WebDavFolder.self) { folder in
                FolderView(folder: folder)
                    .environmentObject(manager)
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("连接 / 刷新") { connect() }.disabled(host.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                configBar
            }
        }
        .onAppear { if !host.isEmpty { connect() } }
    }

    private var configBar: some View {
        VStack(spacing: 6) {
            TextField("WebDAV 地址，如 https://dav.example.com", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            HStack {
                TextField("用户名", text: $user)
                SecureField("密码", text: $pass)
                Button("连接") { connect() }
            }
        }
        .padding(8)
        .background(.bar)
    }

    func connect() { Task { await load(path: "") } }

    func load(path p: String) async {
        isLoading = true
        errorMsg = nil
        do {
            let result = try await WebDavManager.shared.list(host: host, user: user, pass: pass, path: p)
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

    func play(_ item: WebDavItem) {
        guard let url = WebDavManager.shared.resolveURL(host: host, path: item.path) else { return }
        manager.play(url, title: item.name)
    }
}

struct FolderView: View {
    let folder: WebDavFolder
    @AppStorage("webdavHost") private var host = ""
    @AppStorage("webdavUser") private var user = ""
    @AppStorage("webdavPass") private var pass = ""

    @State private var items: [WebDavItem] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    @EnvironmentObject private var manager: PlayerManager

    var body: some View {
        Group {
            if isLoading { ProgressView("加载中…") }
            if let errorMsg { Text(errorMsg).foregroundColor(.red) }
            List {
                ForEach(items) { item in
                    if item.isDirectory {
                        NavigationLink(value: WebDavFolder(path: item.path, name: item.name)) {
                            Label(item.name, systemImage: "folder")
                        }
                    } else {
                        Button { play(item) } label: { Label(item.name, systemImage: "play.circle") }
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
            let result = try await WebDavManager.shared.list(host: host, user: user, pass: pass, path: folder.path)
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

    func play(_ item: WebDavItem) {
        guard let url = WebDavManager.shared.resolveURL(host: host, path: item.path) else { return }
        manager.play(url, title: item.name)
    }
}
