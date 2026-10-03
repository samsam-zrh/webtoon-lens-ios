import Foundation

public struct ChapterURLNavigation: Hashable, Sendable {
    public let previous: URL?
    public let next: URL?
    public let label: String
    public let explanation: String?

    public static func derive(_ address: String) -> ChapterURLNavigation {
        guard let url = try? BrowserAddress.parse(address),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return unavailable("Lien HTTP(S) invalide.")
        }
        let path = components.percentEncodedPath
        let expression = try! NSRegularExpression(
            pattern: #"(?i)(?:^|[/_-])(?:chapter|chapitre|episode|ep|ch)[-_/]?([0-9]+)(?=(?:\.html?)?(?:/|$))"#
        )
        var matches = expression.matches(in: path, range: NSRange(path.startIndex..., in: path))
        let items = (components.percentEncodedQuery ?? "").components(separatedBy: "&")
        let keys = Set(["chapter", "chapitre", "episode", "episode_no"])
        let queryCandidates = items.enumerated().filter { _, item in
            let name = item.components(separatedBy: "=")[0].removingPercentEncoding?.lowercased() ?? ""
            return keys.contains(name)
        }
        if (url.host == "webtoons.com" || url.host?.hasSuffix(".webtoons.com") == true),
           matches.count == 1, queryCandidates.count == 1,
           let match = matches.first, let range = Range(match.range(at: 1), in: path),
           let query = queryCandidates.first {
            let parts = query.element.components(separatedBy: "=")
            let titleKeys = items.filter { $0.components(separatedBy: "=")[0].lowercased() == "title_no" }
            let episodeSlug = (path as NSString).substring(with: match.range).lowercased().contains("episode")
            if parts.count == 2, parts[0].lowercased() == "episode_no",
               titleKeys.count == 1, episodeSlug, Int(parts[1]) != nil, Int(path[range]) != nil {
                // WEBTOON's human-readable path is a slug; episode_no is its route key.
                matches.removeAll()
            }
        }
        guard matches.count + queryCandidates.count == 1 else {
            return unavailable(matches.isEmpty && queryCandidates.isEmpty
                ? "Le chapitre suivant ne peut pas etre deduit de ce lien ; son identifiant peut etre opaque."
                : "Plusieurs numeros de chapitre possibles : navigation desactivee.")
        }
        let digits: String
        let pathRange: Range<String.Index>?
        let queryIndex: Int?
        if let match = matches.first, let range = Range(match.range(at: 1), in: path) {
            digits = String(path[range])
            pathRange = range
            queryIndex = nil
        } else if let candidate = queryCandidates.first {
            let value = candidate.element.components(separatedBy: "=")
            guard value.count == 2 else { return unavailable("Parametre de chapitre invalide.") }
            digits = value[1]
            pathRange = nil
            queryIndex = candidate.offset
        } else {
            return unavailable("Numero de chapitre ambigu.")
        }
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(digits), number >= 1 else {
            return unavailable("Numero de chapitre entier requis, sans depassement.")
        }
        func stepped(_ target: Int) -> URL? {
            let value = String(target)
            let padded = String(repeating: "0", count: max(0, digits.count - value.count)) + value
            if let pathRange {
                components.percentEncodedPath = path.replacingCharacters(in: pathRange, with: padded)
            } else if let queryIndex {
                var updated = items
                let name = updated[queryIndex].components(separatedBy: "=")[0]
                updated[queryIndex] = "\(name)=\(padded)"
                components.percentEncodedQuery = updated.joined(separator: "&")
            }
            return components.url
        }
        return ChapterURLNavigation(
            previous: number > 1 ? stepped(number - 1) : nil,
            next: number < Int.max ? stepped(number + 1) : nil,
            label: "Chapitre \(number)",
            explanation: number == Int.max ? "Numero maximal atteint." : nil
        )
    }

    private static func unavailable(_ reason: String) -> ChapterURLNavigation {
        ChapterURLNavigation(previous: nil, next: nil, label: "", explanation: reason)
    }
}

public struct BrowserFallbackContext: Hashable, Sendable {
    public let requestedURL: URL
    public var resolvedURL: URL?
    public let configuration: String

    public init(requestedURL: URL, resolvedURL: URL? = nil, configuration: String) {
        self.requestedURL = requestedURL
        self.resolvedURL = resolvedURL
        self.configuration = configuration
    }

    public func canCaptureCurrentPage(for url: URL, configuration: String, currentURL: URL?) -> Bool {
        self.configuration == configuration &&
            (url == requestedURL || url == resolvedURL) &&
            currentURL != nil && (currentURL == requestedURL || currentURL == resolvedURL)
    }
}
