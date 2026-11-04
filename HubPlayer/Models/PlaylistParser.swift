import Foundation

enum PlaylistParser {

    /// 解析 M3U / M3U8 文本，返回频道列表
    static func parse(_ text: String) -> [Channel] {
        var channels: [Channel] = []
        let lines = text.components(separatedBy: .newlines)
        var currentTitle: String?
        var currentGroup: String?
        var currentLogo: URL?

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                let name = parseAttribute(line, key: "tvg-name")
                let group = parseAttribute(line, key: "group-title")
                let logo = parseAttribute(line, key: "tvg-logo")

                var title = name ?? ""
                if title.isEmpty, let commaRange = line.range(of: ",") {
                    let after = String(line[line.index(after: commaRange.lowerBound)...])
                    title = after.trimmingCharacters(in: .whitespaces)
                }
                currentTitle = title.isEmpty ? nil : title
                currentGroup = (group?.isEmpty == true) ? nil : group
                currentLogo = (logo != nil) ? URL(string: logo!) : nil

            } else if line.hasPrefix("#") {
                continue

            } else {
                guard let url = URL(string: line) else { continue }
                let ch = Channel(
                    title: currentTitle ?? line,
                    url: url,
                    group: currentGroup ?? "未分组",
                    logo: currentLogo
                )
                channels.append(ch)
                currentTitle = nil
                currentGroup = nil
                currentLogo = nil
            }
        }
        return channels
    }

    /// 从订阅地址拉取并解析
    static func fetch(from urlString: String) async throws -> [Channel] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return parse(text)
    }

    private static func parseAttribute(_ line: String, key: String) -> String? {
        let pattern = #"\#(key)=\"([^\"]*)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }
}
