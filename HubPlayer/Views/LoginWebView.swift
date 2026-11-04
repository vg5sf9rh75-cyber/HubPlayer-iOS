import SwiftUI
import WebKit

/// 通用扫码 / 网页登录壳。
///
/// 打开给定的登录页（夸克、哔哩等都用得到），用户扫码 / 登录后点「保存 Cookie」，
/// 从 `WKHTTPCookieStore` 抓取匹配 `cookieDomain` 的 Cookie 写入 `UserDefaults(storageKey)`。
/// 这样第三方 App 无需逆向各平台的 OAuth，扫码后由系统 WebView 自动持有登录态。
struct LoginWebView: View {
    let title: String
    let loginURL: URL
    let cookieDomain: String
    let storageKey: String

    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?
    @State private var status = "请在下方网页中完成扫码 / 登录…"

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                LoginWebViewRepresentable(webView: $webView, url: loginURL)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存 Cookie") { captureCookies() }
                }
            }
        }
    }

    private func captureCookies() {
        guard let wv = webView else {
            status = "网页尚未加载完成，请稍候"
            return
        }
        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let matched = cookies.filter { $0.domain.contains(self.cookieDomain) }
            let cookieStr = matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            DispatchQueue.main.async {
                if cookieStr.isEmpty {
                    self.status = "未检测到 \(self.cookieDomain) 的登录 Cookie，请先完成扫码登录"
                    return
                }
                UserDefaults.standard.set(cookieStr, forKey: self.storageKey)
                self.status = "已保存 \(matched.count) 个 Cookie"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.dismiss()
                }
            }
        }
    }
}

private struct LoginWebViewRepresentable: UIViewRepresentable {
    @Binding var webView: WKWebView?
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.allowsBackForwardNavigationGestures = true
        wv.load(URLRequest(url: url))
        webView = wv
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
