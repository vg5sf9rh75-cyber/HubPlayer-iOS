import Foundation

// MARK: - TVBox 配置模型（对齐 aiwex.json / FongMi TV 配置格式）

struct TVBoxConfig: Codable {
    var spider: String?          // 爬虫包地址，形如 url;md5;hash
    var wallpaper: String?
    var logo: String?
    var sites: [TVBoxSite]
    var lives: [TVBoxLive]
    var parses: [TVBoxParse]
    var rules: [TVBoxRule]?
    var headers: [TVBoxHeader]?
    var flags: [String]?
    var ads: [String]?
    var doh: [TVBoxDoh]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spider = try c.decodeIfPresent(String.self, forKey: .spider)
        wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        sites = (try? c.decode([TVBoxSite].self, forKey: .sites)) ?? []
        lives = (try? c.decode([TVBoxLive].self, forKey: .lives)) ?? []
        parses = (try? c.decode([TVBoxParse].self, forKey: .parses)) ?? []
        rules = try? c.decode([TVBoxRule].self, forKey: .rules)
        headers = try? c.decode([TVBoxHeader].self, forKey: .headers)
        flags = try? c.decode([String].self, forKey: .flags)
        ads = try? c.decode([String].self, forKey: .ads)
        doh = try? c.decode([TVBoxDoh].self, forKey: .doh)
    }

    private enum CodingKeys: String, CodingKey {
        case spider, wallpaper, logo, sites, lives, parses, rules, headers, flags, ads, doh
    }
}

/// 站点（type=3 为 csp_ 自定义爬虫，type=0/1 为 CMS/xml 等）
struct TVBoxSite: Codable, Identifiable, Hashable {
    var key: String
    var name: String
    var type: Int
    var api: String
    var ext: JSONString?
    var searchable: Int?
    var quickSearch: Int?
    var filterable: Int?
    var changeable: Int?
    var playerType: Int?
    var categories: [String]?
    var style: TVBoxStyle?

    var id: String { key }
    /// csp_ 前缀 => DEX 爬虫类名
    var spiderClass: String? {
        api.hasPrefix("csp_") ? String(api.dropFirst(4)) : nil
    }
    var isCsp: Bool { api.hasPrefix("csp_") }
}

struct TVBoxStyle: Codable, Hashable {
    var type: String?
    var ratio: Double?
}

/// ext 字段可能是字符串，也可能是结构化对象，统一转字符串传给爬虫
enum JSONString: Codable, Hashable {
    case string(String)
    case object(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else {
            // 用 JSONSerialization 兜底保留原始结构文本
            if let dict = try? c.decode([String: JSONValue].self) {
                self = .object(JSONValue.encode(dict))
            } else { self = .string("") }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s), .object(let s): try c.encode(s)
        }
    }
    var text: String {
        switch self { case .string(let s), .object(let s): return s }
    }
}

/// 轻量任意 JSON 值（用于 ext / header / extend）
indirect enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    static func encode(_ dict: [String: JSONValue]) -> String {
        guard let d = try? JSONEncoder().encode(dict) else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }
    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(format: "%.0f", n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        default:
            guard let d = try? JSONEncoder().encode(self) else { return "" }
            return String(data: d, encoding: .utf8) ?? ""
        }
    }
}

struct TVBoxLive: Codable, Identifiable, Hashable {
    var name: String
    var type: Int
    var url: String
    var ua: String?
    var epg: String?
    var playerType: Int?
    var groups: [TVBoxLiveGroup]?
    var channels: [TVBoxChannel]?
    var id: String { name + url }
}

struct TVBoxLiveGroup: Codable, Hashable {
    var name: String?
    var channels: [TVBoxChannel]?
}

struct TVBoxChannel: Codable, Identifiable, Hashable {
    var name: String
    var url: String
    var group: String?
    var logo: String?
    var epg: String?
    var ua: String?
    var id: String { name + url }
}

struct TVBoxParse: Codable, Hashable {
    var name: String
    var type: Int
    var url: String
    var ext: JSONString?
}

struct TVBoxRule: Codable, Hashable {
    var name: String?
    var hosts: [String]?
}

struct TVBoxHeader: Codable, Hashable {
    var host: String
    var header: [String: String]
}

struct TVBoxDoh: Codable, Hashable {
    var name: String
    var url: String
    var ips: [String]?
}

// MARK: - 爬虫返回数据（TVBox 标准 JSON）

struct VodItem: Identifiable, Hashable {
    var id: String
    var name: String
    var pic: String
    var remarks: String
    var year: String
    var area: String
    var typeName: String
    var actor: String
    var director: String
    var content: String
    var playFrom: [String]
    /// 每组选集：[ (集名, 播放标识) ]
    var playGroups: [[VodEpisode]]
    var raw: [String: Any]

    // raw 为 [String:Any] 不参与相等/哈希（navigationDestination 需要 Hashable）
    static func == (a: VodItem, b: VodItem) -> Bool { a.id == b.id && a.name == b.name }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }

    static func parse(_ dict: [String: Any]) -> VodItem {
        func s(_ k: String) -> String { anyString(dict[k]) ?? "" }
        var from = s("vod_play_from").components(separatedBy: "$$$").filter { !$0.isEmpty }
        var urls = s("vod_play_url").components(separatedBy: "$$$")
        // 部分源只给 play_url 不给 play_from；补默认线路，避免详情页「暂无选集」
        if from.isEmpty && !urls.isEmpty { from = ["默认线路"] }
        if urls.isEmpty { urls = [""] }
        var groups: [[VodEpisode]] = []
        for (i, _) in from.enumerated() {
            let seg = i < urls.count ? urls[i] : ""
            // "#" 是选集分隔符，但地址参数里也可能含 "#"：不含 "$" 的片段拼回上一段
            var pairs: [String] = []
            for piece in seg.components(separatedBy: "#") {
                if pairs.isEmpty || piece.contains("$") { pairs.append(piece) }
                else { pairs[pairs.count - 1] += "#" + piece }
            }
            let eps = pairs.compactMap { pair -> VodEpisode? in
                let p = pair.components(separatedBy: "$")
                guard let first = p.first else { return nil }
                let head = first.trimmingCharacters(in: .whitespaces)
                guard !head.isEmpty else { return nil }
                // 只有一段时视作纯地址，而不是把地址当集名
                if p.count == 1 { return VodEpisode(name: "播放", value: head) }
                let value = p.dropFirst().joined(separator: "$").trimmingCharacters(in: .whitespaces)
                return VodEpisode(name: head, value: value)
            }
            groups.append(eps)
        }
        return VodItem(
            id: s("vod_id"), name: s("vod_name"), pic: s("vod_pic"),
            remarks: s("vod_remarks"), year: s("vod_year"), area: s("vod_area"),
            typeName: s("type_name"), actor: s("vod_actor"), director: s("vod_director"),
            content: s("vod_content"), playFrom: from, playGroups: groups, raw: dict)
    }
}

struct VodEpisode: Identifiable, Hashable {
    var id: String { name + value }
    var name: String
    var value: String
}

struct VodCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var filters: [VodFilter]
}

struct VodFilter: Identifiable, Hashable {
    var id: String { key + name }
    var key: String
    var name: String
    var options: [VodFilterOption]
}

struct VodFilterOption: Identifiable, Hashable {
    var id: String { n + v }
    var n: String
    var v: String
}

struct VodPage {
    var list: [VodItem]
    var pageCount: Int
    var total: Int
    var categories: [VodCategory]
    var filters: [String: [VodFilter]]
}

struct PlayResult {
    var url: String
    var parse: Int
    var jx: Int
    var headers: [String: String]
    var contentType: String
    var playUrl: String

    static func parse(_ dict: [String: Any]) -> PlayResult {
        var h: [String: String] = [:]
        if let hd = dict["header"] as? [String: Any] {
            for (k, v) in hd { h[k] = "\(v)" }
        }
        return PlayResult(
            url: (dict["url"] as? String) ?? "",
            parse: anyInt(dict["parse"]) ?? 0,
            jx: anyInt(dict["jx"]) ?? 0,
            headers: h,
            contentType: (dict["contentType"] as? String) ?? "",
            playUrl: (dict["playUrl"] as? String) ?? "")
    }
}

/// 把爬虫返回的 JSON 字符串安全解析成字典（含容错：去 BOM / 空串）
func parseVodJSON(_ text: String) -> [String: Any] {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = clean.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) else { return [:] }
    return obj as? [String: Any] ?? [:]
}

func parseVodPage(_ text: String) -> VodPage {
    let d = parseVodJSON(text)
    let list = (d["list"] as? [[String: Any]] ?? []).map { VodItem.parse($0) }
    var cats: [VodCategory] = []
    if let cls = d["class"] as? [[String: Any]] {
        cats = cls.compactMap { c in
            guard let id = anyString(c["type_id"]), let name = anyString(c["type_name"]) else { return nil }
            return VodCategory(id: id, name: name, filters: [])
        }
    }
    var filters: [String: [VodFilter]] = [:]
    if let f = d["filters"] as? [String: Any] {
        for (tid, val) in f {
            guard let arr = val as? [[String: Any]] else { continue }
            filters[tid] = arr.compactMap { item in
                guard let key = item["key"] as? String, let name = item["name"] as? String else { return nil }
                let opts = (item["value"] as? [[String: Any]] ?? []).compactMap { o -> VodFilterOption? in
                    guard let n = o["n"] as? String, let v = o["v"] as? String else { return nil }
                    return VodFilterOption(n: n, v: v)
                }
                return VodFilter(key: key, name: name, options: opts)
            }
        }
    }
    return VodPage(list: list,
                   pageCount: anyInt(d["pagecount"]) ?? anyInt(d["page"]) ?? 1,
                   total: anyInt(d["total"]) ?? list.count,
                   categories: cats, filters: filters)
}

func parseVodDetail(_ text: String) -> VodItem? {
    let d = parseVodJSON(text)
    guard let arr = d["list"] as? [[String: Any]], let first = arr.first else { return nil }
    return VodItem.parse(first)
}

// MARK: - M3U 直播解析（复用原 PlaylistParser 的逻辑，支持 #EXTGRP / tvg-*）

struct M3UChannel: Identifiable, Hashable {
    var id: String { name + url }
    var name: String
    var url: String
    var group: String
    var logo: String
    var attrs: [String: String]
}

func parseM3U(_ text: String, sourceName: String, defaultUA: String? = nil) -> [M3UChannel] {
    var out: [M3UChannel] = []
    let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    var pending: [String: String] = [:]
    var pendingName = ""
    var pendingGroup = sourceName
    for line in lines {
        if line.hasPrefix("#EXTINF") {
            pending = [:]
            // 抓全部 key="value"（tvg-name / tvg-logo / group-title / ua ...）
            if let regex = try? NSRegularExpression(pattern: #"([a-zA-Z-]+)="([^"]*)""#) {
                let ns = line as NSString
                let range = NSRange(location: 0, length: ns.length)
                for m in regex.matches(in: line, range: range) where m.numberOfRanges >= 3 {
                    let k = ns.substring(with: m.range(at: 1))
                    let v = ns.substring(with: m.range(at: 2))
                    pending[k] = v
                }
            }
            pendingGroup = pending["group-title"] ?? sourceName
            if let comma = line.lastIndex(of: ",") {
                pendingName = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            }
        } else if line.hasPrefix("#EXTGRP") {
            pendingGroup = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("#") || line.isEmpty {
            continue
        } else {
            let name = pendingName.isEmpty ? "频道 \(out.count + 1)" : pendingName
            out.append(M3UChannel(name: name, url: line, group: pendingGroup,
                                  logo: pending["tvg-logo"] ?? "", attrs: pending))
            pendingName = ""
        }
    }
    return out
}
