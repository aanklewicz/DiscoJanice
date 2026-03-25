import SwiftUI
import Foundation

public struct CachedAlbum: Codable {
    public let title: String
    public let artist: String
}

public struct CollectionCache: Codable {
    public let username: String
    public let albums: [CachedAlbum]
    public let lastUpdated: Date
}

public struct HistoryEntry: Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let selectedAt: Date

    public init(title: String, artist: String, selectedAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.selectedAt = selectedAt
    }
}

public struct AlbumSuggestion {
    public let title: String
    public let artist: String
    public let coverURL: String?
    public let musicURL: String?

    public init(title: String, artist: String, coverURL: String?, musicURL: String?) {
        self.title = title
        self.artist = artist
        self.coverURL = coverURL
        self.musicURL = musicURL
    }
}

public final class AlbumSuggestionService {

    public enum ServiceError: Error, LocalizedError {
        case invalidUsername
        case networkFailure(reason: String)
        case parsingFailure(reason: String)
        case noItems
        case outOfRange

        public var errorDescription: String? {
            switch self {
            case .invalidUsername:
                return "The provided username is invalid."
            case .networkFailure(let reason):
                return "Network failure: \(reason)"
            case .parsingFailure(let reason):
                return "Parsing failure: \(reason)"
            case .noItems:
                return "No items found in the collection."
            case .outOfRange:
                return "Randomly chosen item index is out of range."
            }
        }
    }

    private static let cacheKey = "CollectionCache"
    private static let cacheMaxAge: TimeInterval = 3600 // 1 hour
    private static let historyKey = "SelectionHistory"
    private static let exclusionDaysKey = "ExclusionDays"

    public static var exclusionDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: exclusionDaysKey)
            // UserDefaults returns 0 for unset keys, so default to 3
            return UserDefaults.standard.object(forKey: exclusionDaysKey) != nil ? stored : 3
        }
        set {
            UserDefaults.standard.set(newValue, forKey: exclusionDaysKey)
        }
    }

    public init() {}

    // MARK: - Cache

    public static func loadCache() -> CollectionCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(CollectionCache.self, from: data)
    }

    private static func saveCache(_ cache: CollectionCache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func isCacheValid(for username: String) -> Bool {
        guard let cache = Self.loadCache(),
              cache.username == username else { return false }
        return Date().timeIntervalSince(cache.lastUpdated) < Self.cacheMaxAge
    }

    // MARK: - History

    public static func loadHistory() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    public static func saveHistory(_ history: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    public static func recordSelection(title: String, artist: String) {
        var history = loadHistory()
        history.insert(HistoryEntry(title: title, artist: artist), at: 0)
        saveHistory(history)
    }

    private func recentlySelectedTitles() -> Set<String> {
        let days = Self.exclusionDays
        guard days > 0 else { return [] }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        let recent = Self.loadHistory().filter { $0.selectedAt > cutoff }
        return Set(recent.map { "\($0.artist)|\($0.title)" })
    }

    // MARK: - Fetch all albums from Discogs

    private func fetchAllAlbums(for username: String) async throws -> [CachedAlbum] {
        let itemsPerPage = 100

        // Fetch first page to get total count
        var components = URLComponents(string: "https://api.discogs.com/users/\(username)/collection/folders/0/releases")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: String(itemsPerPage))
        ]

        let (firstData, _) = try await urlSessionData(from: components.url!)
        guard let firstJson = try? JSONSerialization.jsonObject(with: firstData, options: []) as? [String: Any] else {
            throw ServiceError.parsingFailure(reason: "Failed to parse first page JSON")
        }

        guard let pagination = firstJson["pagination"] as? [String: Any],
              let totalItems = pagination["items"] as? Int,
              totalItems > 0 else {
            throw ServiceError.noItems
        }

        let totalPages = (totalItems + itemsPerPage - 1) / itemsPerPage

        var allAlbums: [CachedAlbum] = []

        // Parse first page
        if let releases = firstJson["releases"] as? [[String: Any]] {
            allAlbums.append(contentsOf: parseReleases(releases))
        }

        // Fetch remaining pages
        for page in 2...max(1, totalPages) {
            var pageComponents = URLComponents(string: "https://api.discogs.com/users/\(username)/collection/folders/0/releases")!
            pageComponents.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(itemsPerPage))
            ]

            let (pageData, _) = try await urlSessionData(from: pageComponents.url!)
            if let pageJson = try? JSONSerialization.jsonObject(with: pageData, options: []) as? [String: Any],
               let releases = pageJson["releases"] as? [[String: Any]] {
                allAlbums.append(contentsOf: parseReleases(releases))
            }
        }

        return allAlbums
    }

    private func parseReleases(_ releases: [[String: Any]]) -> [CachedAlbum] {
        releases.compactMap { release in
            guard let basicInfo = release["basic_information"] as? [String: Any],
                  let rawTitle = basicInfo["title"] as? String,
                  let artists = basicInfo["artists"] as? [[String: Any]],
                  let firstArtist = artists.first,
                  let rawArtist = firstArtist["name"] as? String else {
                return nil
            }
            let title = Self.stripTrailingNumberSuffix(from: rawTitle)
            let artist = Self.stripTrailingNumberSuffix(from: rawArtist)
            return CachedAlbum(title: title, artist: artist)
        }
    }

    /// Refreshes the cache if stale (>1 hour) or missing, then returns the cached collection.
    public func refreshCacheIfNeeded(for username: String) async throws -> CollectionCache {
        guard !username.isEmpty else { throw ServiceError.invalidUsername }

        if isCacheValid(for: username), let cache = Self.loadCache() {
            return cache
        }

        return try await forceRefresh(for: username)
    }

    /// Always fetches from the API regardless of cache age.
    public func forceRefresh(for username: String) async throws -> CollectionCache {
        guard !username.isEmpty else { throw ServiceError.invalidUsername }

        let albums = try await fetchAllAlbums(for: username)
        let cache = CollectionCache(username: username, albums: albums, lastUpdated: Date())
        Self.saveCache(cache)
        return cache
    }

    // MARK: - Suggest random album (from cache)

    public func suggestRandomAlbum(for username: String) async throws -> AlbumSuggestion {
        let cache = try await refreshCacheIfNeeded(for: username)

        guard !cache.albums.isEmpty else {
            throw ServiceError.noItems
        }

        let recentKeys = recentlySelectedTitles()
        let eligible = cache.albums.filter { !recentKeys.contains("\($0.artist)|\($0.title)") }
        // Fall back to full collection if everything was recently played
        let pool = eligible.isEmpty ? cache.albums : eligible
        let randomAlbum = pool.randomElement()!
        let title = randomAlbum.title
        let artist = randomAlbum.artist

        // Fetch iTunes Search API for artwork and music url
        let artistTerm = artist.replacingOccurrences(of: "&", with: "and")
        let titleTerm = title.replacingOccurrences(of: "&", with: "and")
        let searchTerm = "\(artistTerm) \(titleTerm)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard !searchTerm.isEmpty else {
            return AlbumSuggestion(title: title, artist: artist, coverURL: nil, musicURL: nil)
        }

        let itunesURLString = "https://itunes.apple.com/search?term=\(searchTerm)&entity=album"
        guard let itunesURL = URL(string: itunesURLString) else {
            return AlbumSuggestion(title: title, artist: artist, coverURL: nil, musicURL: nil)
        }

        let (itunesData, _) = try await urlSessionData(from: itunesURL)

        guard
            let itunesJson = try? JSONSerialization.jsonObject(with: itunesData, options: []) as? [String: Any],
            let results = itunesJson["results"] as? [[String: Any]],
            let firstResult = results.first
        else {
            return AlbumSuggestion(title: title, artist: artist, coverURL: nil, musicURL: nil)
        }

        let artworkUrl100 = firstResult["artworkUrl100"] as? String
        let collectionViewUrl = firstResult["collectionViewUrl"] as? String

        let artwork300: String? = artworkUrl100?.replacingOccurrences(of: "100x100", with: "300x300")

        return AlbumSuggestion(title: title, artist: artist, coverURL: artwork300, musicURL: collectionViewUrl)
    }

    // MARK: - Helpers

    private func urlSessionData(from url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(from: url)
        } catch {
            throw ServiceError.networkFailure(reason: error.localizedDescription)
        }
    }

    private static func stripTrailingNumberSuffix(from string: String) -> String {
        // regex: " *\\([0-9]*\\)$" - remove trailing space(s) + (number)
        let pattern = #" *\([0-9]*\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        let modString = regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
        return modString
    }
}
