import Foundation

/// 夸克网盘文件节点
struct QuarkFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let fid: String
    let isDir: Bool
    let size: Int64

    var sizeText: String {
        guard size > 0 else { return "" }
        let kb = Double(size) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}

/// 夸克网盘（pan.quark.cn）直链管理器
///
/// 说明：夸克没有给第三方 App 的公开 OAuth，最稳妥的个人用法是「Cookie 登录」——
/// 在电脑浏览器登录 pan.quark.cn 后，从开发者工具（Network 面板 / Application → Cookies）
/// 复制 `kpsid`（或整段 cookie 字符串）填到 App 里即可。本类只负责：
///   1. 列出某个目录下的文件
///   2. 对视频文件换取可播放的直链（download_url）
/// 真实播放地址由 AVPlayer 配合 Referer/Cookie 头拉流。
final class QuarkManager {
    static let shared = QuarkManager()

    private let apiBase = "https://drive-pc.quark.cn/1/clouddrive"
    /// 根目录 fid
    static let rootFid = "0"

    private func headers(cookie: String) -> [String: String] {
        var h: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
        ]
        if !cookie.isEmpty {
            h["Cookie"] = cookie
        }
        return h
    }

    /// 列出目录
    func list(pdirFid: String, cookie: String, page: Int = 1, size: Int = 100) async throws -> [QuarkFile] {
        var comps = URLComponents(string: apiBase + "/file/list")!
        comps.queryItems = [
            .init(name: "pr", value: "p"),
            .init(name: "pu", value: "1"),
            .init(name: "pdir_fid", value: pdirFid),
            .init(name: "_page", value: "\(page)"),
            .init(name: "_size", value: "\(size)"),
            .init(name: "fr", value: "pc"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        for (k, v) in headers(cookie: cookie) { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.assertHTTP(resp)
        let json = try Self.json(data)
        guard let dataObj = json["data"] as? [String: Any],
              let list = dataObj["list"] as? [[String: Any]] else {
            throw QuarkError.message("返回格式异常")
        }
        return list.compactMap { item -> QuarkFile? in
            guard let name = item["file_name"] as? String,
                  let fid = item["fid"] as? String else { return nil }
            let isDir = (item["dir"] as? Bool) == true
            let size = (item["size"] as? Int64) ?? 0
            return QuarkFile(name: name, fid: fid, isDir: isDir, size: size)
        }
    }

    /// 换取文件直链（download_url）。返回 (直链, 文件名)
    func getDownloadURL(fid: String, cookie: String) async throws -> (url: String, name: String) {
        var req = URLRequest(url: URL(string: apiBase + "/file/download")!)
        req.httpMethod = "POST"
        for (k, v) in headers(cookie: cookie) { req.setValue(v, forHTTPHeaderField: k) }
        let body: [String: Any] = [
            "fids": [fid],
            "resolutions": "",
            "platform": "pc",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.assertHTTP(resp)
        let json = try Self.json(data)
        guard let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let name = first["file_name"] as? String else {
            throw QuarkError.message("未获取到文件信息")
        }
        // download_url 可能为空（部分视频需二次换取），这里直接返回拿到的值
        let url = (first["download_url"] as? String) ?? ""
        if url.isEmpty {
            throw QuarkError.message("直链为空，可能该文件类型不支持直链播放")
        }
        return (url: url, name: name)
    }

    // MARK: - 解析辅助

    private static func assertHTTP(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw QuarkError.message("不是 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            throw QuarkError.message("HTTP \(http.statusCode)")
        }
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuarkError.message("JSON 解析失败")
        }
        if let code = obj["code"] as? Int, code != 0 {
            let msg = (obj["message"] as? String) ?? "错误码 \(code)"
            throw QuarkError.message(msg)
        }
        return obj
    }
}

enum QuarkError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}
