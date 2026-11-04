import SwiftUI
import WebKit

/// 哔哩哔哩入口。
///
/// 由于 B 站没有给第三方播放器开放直链 / 播放授权，本页采用「内置浏览器 + 扫码登录」方案：
/// 用户在 WebView 里扫码登录后直接观看（登录态通过 Cookie 注入）。
/// 你之前说的“B站我自己扫码就可以”，正是对应这里的扫码登录入口。
struct BiliView: View {
    @AppStorage("biliCookie") private var cookie = ""
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            VStack {
                if cookie.isEmpty {
                    ContentUnavailableFallback(
                        title: "未登录哔哩哔哩",
                        subtitle: "点下方“扫码登录”，在网页中扫码后保存 Cookie，即可在内部浏览器观看"
                    )
                    Button("扫码登录") { showLogin = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                } else {
                    BiliWebView(cookie: cookie)
                }
            }
            .navigationTitle("哔哩")
            .toolbar {
                if !cookie.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("重新登录") { showLogin = true }
                    }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginWebView(
                    title: "哔哩扫码登录",
                    loginURL: URL(string: "https://passport.bilibili.com/h5-app/passport/login")!,
                    cookieDomain: "bilibili.com",
                    storageKey: "biliCookie"
                )
            }
        }
    }
}

/// 注入 Cookie 后内嵌打开移动版 B 站，用户登录态下直接浏览 / 观看。
private struct BiliWebView: UIViewRepresentable {
    let cookie: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let store = config.websiteDataStore.httpCookieStore
        for p in cookie.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let kv = p.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let props: [HTTPCookiePropertyKey: Any] = [
                .domain: ".bilibili.com",
                .path: "/",
                .name: String(kv[0]),
                .value: String(kv[1]),
            ]
            if let c = HTTPCookie(properties: props) {
                store.setCookie(c) {}
            }
        }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.load(URLRequest(url: URL(string: "https://m.bilibili.com")!))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
