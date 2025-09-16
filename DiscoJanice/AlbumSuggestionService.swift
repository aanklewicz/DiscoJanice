import SwiftUI
import Foundation

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
    
    public init() {}
    
    public func suggestRandomAlbum(for username: String) async throws -> AlbumSuggestion {
        guard !username.isEmpty else {
            throw ServiceError.invalidUsername
        }
        
        // 1) Fetch first page metadata to get pagination.items
        let firstPageURL = URL(string: "https://api.discogs.com/users/\(username)/collection/folders/0/releases")!
        
        let (firstData, _) = try await urlSessionData(from: firstPageURL)
        guard
            let firstJson = try? JSONSerialization.jsonObject(with: firstData, options: []) as? [String: Any]
        else {
            throw ServiceError.parsingFailure(reason: "Failed to parse first page JSON")
        }
        
        guard
            let pagination = firstJson["pagination"] as? [String: Any],
            let totalItems = pagination["items"] as? Int,
            totalItems > 0
        else {
            throw ServiceError.noItems
        }
        
        // Choose a random item index in 1...totalItems
        let randomItem = Int.random(in: 1...totalItems)
        
        // Compute page and indexInPage (0-based)
        let itemsPerPage = 100
        let page = (randomItem - 1) / itemsPerPage + 1
        let indexInPage = (randomItem - 1) % itemsPerPage
        
        // 2) Fetch releases for that page
        var components = URLComponents(string: "https://api.discogs.com/users/\(username)/collection/folders/0/releases")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(itemsPerPage))
        ]
        guard let pageURL = components.url else {
            throw ServiceError.invalidUsername // unlikely but fallback
        }
        
        let (pageData, _) = try await urlSessionData(from: pageURL)
        
        guard
            let pageJson = try? JSONSerialization.jsonObject(with: pageData, options: []) as? [String: Any]
        else {
            throw ServiceError.parsingFailure(reason: "Failed to parse page JSON")
        }
        
        guard
            let releases = pageJson["releases"] as? [[String: Any]],
            indexInPage < releases.count
        else {
            throw ServiceError.outOfRange
        }
        
        let release = releases[indexInPage]
        guard
            let basicInfo = release["basic_information"] as? [String: Any],
            let rawTitle = basicInfo["title"] as? String,
            let artists = basicInfo["artists"] as? [[String: Any]],
            let firstArtist = artists.first,
            let rawArtist = firstArtist["name"] as? String
        else {
            throw ServiceError.parsingFailure(reason: "Missing release or artist information")
        }
        
        let title = AlbumSuggestionService.stripTrailingNumberSuffix(from: rawTitle)
        let artist = AlbumSuggestionService.stripTrailingNumberSuffix(from: rawArtist)
        
        // 3) Fetch iTunes Search API for artwork and music url
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
