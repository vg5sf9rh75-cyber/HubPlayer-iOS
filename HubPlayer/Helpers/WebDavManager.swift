import Foundation

struct WebDavItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String       // 服务器上的绝对路径，如 /dav/video/
    let isDirectory: Bool
}

final class WebDavManager {
    static let shared = WebDavManager()

    func baseURL(host: String) -> URL? {
        var h = host
        while h.hasSuffix("/") { h.removeLast() }
        return URL(string: h + "/")
    }

    func resolveURL(host: String, path: String) -> URL? {
        guard let base = baseURL(host: host) else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        var p = path
        while p.hasPrefix("/") { p.removeFirst() }
        return URL(string: p, relativeTo: base)
    }

    func list(host: String, user: String, pass: String, path: String) async throws -> [WebDavItem] {
        guard let url = resolveURL(host: host, path: path) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                   "<D:propfind xmlns:D=\"DAV:\"><D:prop><D:resourcetype/><D:displayname/></D:prop></D:propfind>"
        request.httpBody = body.data(using: .utf8)

        if let u = URL(string: host) {
            let cred = URLCredential(user: user, password: pass, persistence: .forSession)
            let space = URLProtectionSpace(host: u.host ?? "",
                                          port: u.port ?? 0,
                                          protocol: u.scheme ?? "https",
                                          realm: nil,
                                          authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            URLCredentialStorage.shared.set(cred, for: space)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "WebDAV", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "服务器返回错误码 \(http.statusCode)"])
        }

        let parser = WDXMLParser()
        let xp = XMLParser(data: data)
        xp.delegate = parser
        xp.parse()

        let requested = resolveURL(host: host, path: path)?.absoluteString ?? path
        return parser.items
            .filter { $0.name != "." && $0.name != ".." }
            .filter { $0.path != requested && $0.path != requested + "/" }
    }
}

private class WDXMLParser: NSObject, XMLParserDelegate {
    var items: [WebDavItem] = []
    private var inHref = false
    private var hrefBuffer = ""
    private var inName = false
    private var nameBuffer = ""
    private var isCollection = false

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        let local = (qName ?? element).lowercased()
        if local == "response" {
            isCollection = false
            hrefBuffer = ""
            nameBuffer = ""
        } else if local == "href" {
            inHref = true
            hrefBuffer = ""
        } else if local == "displayname" {
            inName = true
            nameBuffer = ""
        } else if local == "collection" {
            isCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inHref { hrefBuffer += string }
        if inName { nameBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = (qName ?? element).lowercased()
        if local == "href" {
            inHref = false
        } else if local == "displayname" {
            inName = false
        } else if local == "response" {
            let href = hrefBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = nameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { return }
            let displayName = name.isEmpty ? (href as NSString).lastPathComponent : name
            let isDir = isCollection || href.hasSuffix("/")
            items.append(WebDavItem(name: displayName, path: href, isDirectory: isDir))
        }
    }
}
