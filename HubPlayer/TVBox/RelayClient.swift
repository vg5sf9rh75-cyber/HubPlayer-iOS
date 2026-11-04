import Foundation

// MARK: - 单机本地引擎（无中继）
//
// 这个版本不需要任何第二台设备：
//   · 配置：URL 拉取 / 粘贴 JSON / 粘贴 base64
//   · 站点：自定义 CMS(苹果CMS v10) / 直链 JSON / ext 直读
//   · 直播：M3U 地址 / 粘贴 M3U 文本
//   · 解析：parses 解析接口
// 配置里的 csp_ 条目仅作为占位（安卓 DEX 插件），单机版不内置 DEX 运行时；
// 后期可在「设置 → 自定义站点」自行换成任意可直连的采集接口。

enum RelayError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int)
    case server(String)
    case decode(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置站点，请到「设置」添加自定义站点或配置地址"
        case .badURL: return "地址格式不正确"
        case .http(let c): return "服务器返回 HTTP \(c)"
        case .server(let m): return "请求失败：\(m)"
        case .decode(let m): return "数据解析失败：\(m)"
        case .unsupported(let m): return m
        }
    }
}

/// 任意 JSON 标量转字符串（苹果CMS 常把 id / pagecount 写成数字）
func anyString(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

func anyInt(_ v: Any?) -> Int? {
    if let n = v as? NSNumber { return n.intValue }
    if let s = v as? String { return Int(s) }
    return nil
}

final class RelayClient {
    static let shared = RelayClient()
    private let ud = UserDefaults.standard

    // MARK: - 用户可配置项（全部本地持久化）

    /// TVBox 配置地址，可留空
    var configURL: String {
        get { ud.string(forKey: "tvbox.configURL") ?? "" }
        set { ud.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "tvbox.configURL") }
    }
    /// 粘贴的配置内容（JSON / base64），优先级高于 configURL
    var pastedConfig: String {
        get { ud.string(forKey: "tvbox.pastedConfig") ?? "" }
        set { ud.set(newValue, forKey: "tvbox.pastedConfig") }
    }
    /// 粘贴的 M3U 文本
    var pastedM3U: String {
        get { ud.string(forKey: "tvbox.pastedM3U") ?? "" }
        set { ud.set(newValue, forKey: "tvbox.pastedM3U") }
    }
    /// 自定义站点：key/name/type/api/ext 均为字符串
    var customSites: [[String: String]] {
        get { ud.array(forKey: "tvbox.customSites") as? [[String: String]] ?? [] }
        set { ud.set(newValue, forKey: "tvbox.customSites") }
    }
    /// 自定义直播源：name/url
    var customLives: [[String: String]] {
        get { ud.array(forKey: "tvbox.customLives") as? [[String: String]] ?? [] }
        set { ud.set(newValue, forKey: "tvbox.customLives") }
    }
    /// 兼容旧界面字段；单机版恒为空（不发起任何中继请求）
    var baseURL: String {
        get { ud.string(forKey: "tvbox.legacyRelay") ?? "" }
        set { ud.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "tvbox.legacyRelay") }
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 45
        return URLSession(configuration: c)
    }()

    // MARK: - 本地自检（替代原 /ping）

    func ping() async throws -> [String: Any] {
        let cfg = try await fetchConfig()
        let usable = cfg.sites.filter { !$0.isCsp }.count
        return [
            "ok": true,
            "local": true,
            "sites": cfg.sites.count,
            "usable": usable,
            "lives": cfg.lives.count,
            "parses": cfg.parses.count,
            "spiderLoaded": false
        ]
    }

    // MARK: - 采集调用（本地执行，替代 POST /spider）

    func callSpider(api: String, ext: String = "", method: String,
                    args: [String: Any] = [:]) async throws -> String {
        // 0) 内置演示站点：离线验证「首页 → 详情 → 选集 → 播放」整条链路
        if api == "hub://demo" {
            return demoResponse(method: method, args: args)
        }

        // 1) DEX 插件站点只作占位；若 ext 直接指向可直读的 JSON 则仍可展示
        if api.hasPrefix("csp_") {
            if (method == "homeContent" || method == "categoryContent"),
               let u = firstHTTPURL(in: ext) {
                let text = try await fetchText(u)
                if parseVodJSON(text)["list"] != nil { return text }
            }
            throw RelayError.unsupported(
                "「\(api)」是安卓 DEX 插件站点，单机版不内置 DEX 运行时。请到「设置 → 自定义站点」添加 CMS / 直链接口后使用。")
        }

        // 2) 播放：把选集值规范化成 CMS 标准 play 结果
        if method == "playerContent" {
            return try playerResult(value: args["id"] as? String ?? "", ext: ext, api: api)
        }

        // 3) 可直连的采集接口
        guard let base = URL(string: api),
              let scheme = base.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            if let u = firstHTTPURL(in: ext) { return try await fetchText(u) }
            throw RelayError.notConfigured
        }

        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw RelayError.badURL
        }
        var items = comps.queryItems ?? []
        func put(_ k: String, _ v: String) {
            items.removeAll { $0.name == k }
            items.append(URLQueryItem(name: k, value: v))
        }
        switch method {
        case "homeContent", "homeVideoContent":
            put("ac", "videolist")
            put("pg", "1")
        case "categoryContent":
            put("ac", "videolist")
            put("t", args["tid"] as? String ?? "")
            put("pg", args["pg"] as? String ?? "1")
            for (k, v) in (args["extend"] as? [String: String] ?? [:]) { put(k, v) }
        case "detailContent":
            put("ac", "videolist")
            put("ids", (args["ids"] as? [String] ?? []).joined(separator: ","))
        case "searchContent":
            put("ac", "videolist")
            put("wd", args["key"] as? String ?? "")
            put("pg", args["pg"] as? String ?? "1")
        default:
            break
        }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { throw RelayError.badURL }
        return try await fetchText(url.absoluteString)
    }

    // MARK: - 便捷方法（对齐 com.github.catvod.crawler.Spider，签名保持不变）

    func homeContent(api: String, ext: String, filter: Bool = true) async throws -> VodPage {
        let s = try await callSpider(api: api, ext: ext, method: "homeContent", args: ["filter": filter])
        return parseVodPage(s)
    }

    func homeVideoContent(api: String, ext: String) async throws -> [VodItem] {
        let s = try await callSpider(api: api, ext: ext, method: "homeVideoContent")
        return parseVodPage(s).list
    }

    func categoryContent(api: String, ext: String, tid: String, page: Int,
                         filter: Bool = true, extend: [String: String] = [:]) async throws -> VodPage {
        let s = try await callSpider(api: api, ext: ext, method: "categoryContent",
                                     args: ["tid": tid, "pg": String(page), "filter": filter, "extend": extend])
        return parseVodPage(s)
    }

    func detailContent(api: String, ext: String, id: String) async throws -> VodItem? {
        let s = try await callSpider(api: api, ext: ext, method: "detailContent", args: ["ids": [id]])
        return parseVodDetail(s)
    }

    func searchContent(api: String, ext: String, key: String,
                       quick: Bool = false, page: Int = 1) async throws -> VodPage {
        let s = try await callSpider(api: api, ext: ext, method: "searchContent",
                                     args: ["key": key, "quick": quick, "pg": String(page)])
        return parseVodPage(s)
    }

    func playerContent(api: String, ext: String, flag: String, id: String,
                       vipFlags: [String] = []) async throws -> PlayResult {
        let s = try await callSpider(api: api, ext: ext, method: "playerContent",
                                     args: ["flag": flag, "id": id, "vipFlags": vipFlags])
        return PlayResult.parse(parseVodJSON(s))
    }

    func liveContent(api: String, ext: String, group: String = "") async throws -> String {
        ""
    }

    func action(api: String, ext: String, action: String) async throws -> String {
        ""
    }

    // MARK: - 配置（粘贴 > URL > 空模板，再合并自定义项）

    func fetchConfig() async throws -> TVBoxConfig {
        var root: [String: Any] = [:]
        let text: String
        if !pastedConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = pastedConfig
        } else if !configURL.isEmpty {
            text = try await fetchText(configURL)
        } else {
            text = ""
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            root = try decodeConfigObject(text)
        }

        var sites = root["sites"] as? [[String: Any]] ?? []
        for (i, c) in customSites.enumerated() {
            let api = c["api"] ?? ""
            guard !api.isEmpty else { continue }
            let key = (c["key"] ?? "").isEmpty ? "custom_\(i)" : (c["key"] ?? "")
            var d: [String: Any] = [
                "key": key,
                "name": (c["name"] ?? "").isEmpty ? "自定义站点" : (c["name"] ?? ""),
                "type": Int(c["type"] ?? "0") ?? 0,
                "api": api,
                "searchable": 1,
                "filterable": 0
            ]
            if let e = c["ext"], !e.isEmpty { d["ext"] = e }
            sites.append(d)
        }

        var lives = root["lives"] as? [[String: Any]] ?? []
        for c in customLives {
            let url = c["url"] ?? ""
            guard !url.isEmpty else { continue }
            lives.append(["name": (c["name"] ?? "").isEmpty ? "自定义直播" : (c["name"] ?? ""),
                          "type": 0, "url": url])
        }
        if !pastedM3U.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lives.append(["name": "粘贴的直播源", "type": 0, "url": "hub://pasted"])
        }

        root["sites"] = sites
        root["lives"] = lives
        if root["parses"] == nil { root["parses"] = [] }
        let data = try JSONSerialization.data(withJSONObject: root)
        do {
            return try JSONDecoder().decode(TVBoxConfig.self, from: data)
        } catch {
            throw RelayError.decode("配置格式无法识别：\(error.localizedDescription)")
        }
    }

    private func decodeConfigObject(_ text: String) throws -> [String: Any] {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\u{FEFF}") { t = String(t.dropFirst()) }
        if let d = t.data(using: .utf8),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { return o }
        let compact = t.components(separatedBy: .whitespacesAndNewlines).joined()
        if let b = Data(base64Encoded: compact, options: .ignoreUnknownCharacters),
           let o = (try? JSONSerialization.jsonObject(with: b)) as? [String: Any] { return o }
        // 容错：配置前后带说明文字时，截取最外层 {...}
        if let a = t.range(of: "{"), let z = t.range(of: "}", options: .backwards) {
            let sub = String(t[a.lowerBound..<z.upperBound])
            if let d = sub.data(using: .utf8),
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { return o }
        }
        throw RelayError.decode("配置不是有效 JSON / base64")
    }

    // MARK: - 资源

    /// 拉取文本；hub://pasted 直接返回粘贴的 M3U
    func fetchText(_ urlString: String, ua: String? = nil) async throws -> String {
        if urlString == "hub://pasted" { return pastedM3U }
        guard let url = URL(string: urlString) else { throw RelayError.badURL }
        var req = URLRequest(url: url)
        if let ua, !ua.isEmpty { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
            throw RelayError.http(h.statusCode)
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// 解析接口（parses）：把网页/加密地址交给解析服务换真实播放地址
    func parse(parseURL: String, target: String) async throws -> String {
        guard let u = URL(string: parseURL + (target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) else {
            throw RelayError.badURL
        }
        let text = try await fetchText(u.absoluteString)
        let d = parseVodJSON(text)
        if let url = d["url"] as? String, !url.isEmpty { return url }
        if let inner = d["data"] as? [String: Any], let u2 = inner["url"] as? String { return u2 }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 播放地址规范化

    /// 选集值 → CMS 标准 play 结果。
    /// 兼容「名称$地址」「$$$ 多线路」「片段内 #」「相对路径」，并标出是否需要解析接口。
    private func playerResult(value raw: String, ext: String, api: String) throws -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { throw RelayError.decode("选集地址为空，源站未返回播放地址") }
        if let sep = v.range(of: "$$$") { v = String(v[..<sep.lowerBound]) }
        if let dollar = v.range(of: "$") { v = String(v[dollar.upperBound...]) }
        if let hash = v.range(of: "#"), !v.lowercased().hasPrefix("http") {
            v = String(v[hash.upperBound...])
        }
        v = v.trimmingCharacters(in: .whitespacesAndNewlines)

        var target = v
        if !isPlayableURL(v),
           let baseStr = firstHTTPURL(in: ext) ?? firstHTTPURL(in: api),
           let baseURL = URL(string: baseStr),
           let u = URL(string: v, relativeTo: baseURL) {
            target = u.absoluteString
        }

        let direct = isPlayableURL(target)
        let obj: [String: Any] = [
            "url": target,
            "parse": direct ? 0 : 1,
            "jx": direct ? 0 : 1,
            "header": [:],
            "contentType": ""
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: d, encoding: .utf8) else {
            throw RelayError.decode("播放结果生成失败")
        }
        return s
    }

    private func isPlayableURL(_ s: String) -> Bool {
        let t = s.lowercased()
        return t.hasPrefix("http://") || t.hasPrefix("https://")
            || t.hasPrefix("rtmp://") || t.hasPrefix("rtsp://")
    }

    // MARK: - 内置演示站点（离线验证播放链路，可随时删除）

    private func demoResponse(method: String, args: [String: Any]) -> String {
        let apple = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
        let mux = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
        func item(_ id: String, _ name: String, _ url: String, _ note: String) -> [String: Any] {
            ["vod_id": id, "vod_name": name, "vod_pic": "", "vod_remarks": "可直接播放",
             "vod_year": "2026", "vod_area": "演示", "type_name": "测试线路",
             "vod_actor": "", "vod_director": "", "vod_content": note,
             "vod_play_from": "直连", "vod_play_url": "第1集$" + url]
        }
        let all = [
            item("1", "演示 · Apple HLS", apple, "Apple 官方公开 HLS 测试流。能出画面说明本机播放链路正常，问题只在配置源。"),
            item("2", "演示 · Mux HLS", mux, "Mux 公开多码率测试流。")
        ]
        var list = all
        switch method {
        case "searchContent":
            let k = (args["key"] as? String ?? "").lowercased()
            if !k.isEmpty {
                list = all.filter { ($0["vod_name"] as? String ?? "").lowercased().contains(k) }
            }
        case "detailContent":
            let ids = args["ids"] as? [String] ?? []
            list = all.filter { ids.contains($0["vod_id"] as? String ?? "") }
        default:
            break
        }
        let obj: [String: Any] = [
            "list": list,
            "class": [["type_id": "1", "type_name": "演示"]],
            "page": 1, "pagecount": 1, "total": list.count, "code": 1
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let s = String(data: d, encoding: .utf8) else { return "{\"list\":[]}" }
        return s
    }

    // MARK: - 小工具

    private func quoted(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
              let q = String(data: d, encoding: .utf8) else { return "\"\"" }
        return q
    }

    private func firstHTTPURL(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("http"), !t.contains(" ") { return t }
        if let r = t.range(of: #"https?://[^\s"'，,]+"#, options: .regularExpression) {
            return String(t[r])
        }
        return nil
    }
}
