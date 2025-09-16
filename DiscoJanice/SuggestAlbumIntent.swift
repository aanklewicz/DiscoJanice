import AppIntents
import Foundation

struct SuggestAlbumIntent: AppIntent, Predictable {
    static var title: LocalizedStringResource = "Suggest an Album"
    static var description: IntentDescription = "Suggest a random album from your Discogs collection."
    
    @Parameter(title: "Discogs Username")
    var username: String? = nil
    
    static var suggestedInvocationPhrase: String? = "Suggest an album"
    
    func perform() async throws -> some IntentResult {
        let resolvedUsername: String
        if let username = username, !username.isEmpty {
            resolvedUsername = username
        } else if let storedUsername = UserDefaults.standard.string(forKey: "DiscogsUsername"), !storedUsername.isEmpty {
            resolvedUsername = storedUsername
        } else {
            return .result(dialog: .init("Please set your Discogs username in the app settings."))
        }
        
        let album = try await AlbumSuggestionService().suggestRandomAlbum(for: resolvedUsername)
        let responseString = "How about '\(album.title)' by \(album.artist)?"
        return .result(value: responseString, dialog: .init(responseString))
    }
}

extension SuggestAlbumIntent: ProvidesDialog {
    static var dialog: IntentDialog? { nil }
}
