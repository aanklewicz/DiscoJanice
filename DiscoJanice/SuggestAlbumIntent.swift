import AppIntents
import Foundation

struct SuggestAlbumIntent: AppIntent {
    typealias Output = String
    static var title: LocalizedStringResource = "Suggest an Album"
    static var description: IntentDescription = "Suggest a random album from your Discogs collection."
    
    @Parameter(title: "Discogs Username")
    var username: String?
    
    static var suggestedInvocationPhrase: String? = "Suggest an album"
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let resolvedUsername: String
        if let username = username, !username.isEmpty {
            resolvedUsername = username
        } else if let storedUsername = UserDefaults.standard.string(forKey: "DiscogsUsername"), !storedUsername.isEmpty {
            resolvedUsername = storedUsername
        } else {
            return .result(value: "Please set your Discogs username in the app settings.")
        }

        let album = try await AlbumSuggestionService().suggestRandomAlbum(for: resolvedUsername)
        let responseString = "How about '\(album.title)' by \(album.artist)?"
        return .result(value: responseString)
    }
}

