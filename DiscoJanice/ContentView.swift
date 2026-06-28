//
//  ContentView.swift
//  DiscoJanice
//
//  Created by Adam Anklewicz on 2025-01-18.
//

import SwiftUI
import Foundation
import Network
import AVFoundation
import UIKit

class Speaker: NSObject {
    
    static let shared = Speaker()
    
    lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    
    func speak(_ string: String) {
        let utterance = AVSpeechUtterance(string: string)
        synthesizer.speak(utterance)
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(true)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .interruptSpokenAudioAndMixWithOthers)
    }
        
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct ContentView: View {
    @State private var discogsUsername: String = UserDefaults.standard.string(forKey: "DiscogsUsername") ?? ""
    @State private var albumTitle: String = "Album Title"
    @State private var artistName: String = "Artist"
    @State private var albumCoverUrl: String? = nil
    @State private var albumMusicUrl: String? = nil
    @State private var isSonosEnabled: Bool = ContentView.boolDefaultTrue(forKey: "SonosEnabled")
    @State private var isSiriEnabled: Bool = ContentView.boolDefaultTrue(forKey: "SiriEnabled")
    @State private var selectedTab: Int = 0

    private let cloud = NSUbiquitousKeyValueStore.default

    /// Reads a Bool from UserDefaults, defaulting to `true` when the key has never been set.
    /// This keeps both integrations on by default for new and existing users.
    private static func boolDefaultTrue(forKey key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AlbumView(discogsUsername: discogsUsername, albumTitle: $albumTitle, artistName: $artistName, albumCoverUrl: $albumCoverUrl, albumMusicUrl: $albumMusicUrl, isSonosEnabled: isSonosEnabled, isSiriEnabled: isSiriEnabled)
                .tabItem {
                    Label("Album", systemImage: "music.quarternote.3")
                }
                .disabled(discogsUsername.isEmpty)
                .tag(0)

            CollectionView(discogsUsername: discogsUsername)
                .tabItem {
                    Label("Collection", systemImage: "list.bullet")
                }
                .disabled(discogsUsername.isEmpty)
                .tag(1)

            HistoryView(albumTitle: $albumTitle, artistName: $artistName, albumCoverUrl: $albumCoverUrl, albumMusicUrl: $albumMusicUrl, selectedTab: $selectedTab)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(2)

            SettingsView(discogsUsername: $discogsUsername, isSonosEnabled: $isSonosEnabled, isSiriEnabled: $isSiriEnabled)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .onAppear {
            pullFromCloud()
            cloud.synchronize()
        }
        // Use SwiftUI's managed subscription instead of NotificationCenter.addObserver.
        // The old code registered a new block observer on every .onAppear and never
        // removed it, so observers accumulated for the lifetime of the process. Over a
        // long macOS session each iCloud change notification fanned out to every leaked
        // observer (all on the main queue), eventually saturating the main thread and
        // freezing the UI. onReceive is tied to the view lifecycle and is not duplicated.
        .onReceive(NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )) { _ in
            pullFromCloud()
        }
    }

    private func pullFromCloud() {
        if let cloudUsername = cloud.string(forKey: "DiscogsUsername"), !cloudUsername.isEmpty {
            discogsUsername = cloudUsername
            UserDefaults.standard.set(cloudUsername, forKey: "DiscogsUsername")
        }
        if cloud.object(forKey: "SonosEnabled") != nil {
            isSonosEnabled = cloud.bool(forKey: "SonosEnabled")
            UserDefaults.standard.set(isSonosEnabled, forKey: "SonosEnabled")
        }
        if cloud.object(forKey: "SiriEnabled") != nil {
            isSiriEnabled = cloud.bool(forKey: "SiriEnabled")
            UserDefaults.standard.set(isSiriEnabled, forKey: "SiriEnabled")
        }
        if cloud.object(forKey: "ExclusionDays") != nil {
            let days = Int(cloud.longLong(forKey: "ExclusionDays"))
            AlbumSuggestionService.exclusionDays = days
        }
        _ = AlbumSuggestionService.mergeHistory()
    }
}

struct AlbumView: View {
    var discogsUsername: String
    @Binding var albumTitle: String
    @Binding var artistName: String
    @Binding var albumCoverUrl: String?
    @Binding var albumMusicUrl: String?
    var isSonosEnabled: Bool
    var isSiriEnabled: Bool
    @State private var isLoading: Bool = false

    private var albumCoverSize: CGFloat {
        ProcessInfo.processInfo.isiOSAppOnMac ? 450 : 300
    }

    var body: some View {
        ZStack {
            if let albumCoverUrl = albumCoverUrl, let url = URL(string: albumCoverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .blur(radius: 60)
                        .saturation(0.5)
                        .overlay(Color.black.opacity(0.3))
                } placeholder: {
                    Color.clear
                }
            }

            VStack {
                if let albumCoverUrl = albumCoverUrl, let url = URL(string: albumCoverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: albumCoverSize, height: albumCoverSize)
                    } placeholder: {
                        ProgressView()
                            .frame(width: albumCoverSize, height: albumCoverSize)
                    }
                    .padding(.bottom, 20)
                    .shadow(color: .black, radius: 10, x: 0, y: 0)
                } else {
                    albumPlaceholder
                        .padding(.bottom, 20)
                        .shadow(color: .black, radius: 10, x: 0, y: 0)
                }

                if !(albumTitle == "Album Title") {
                    Text(albumTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(albumCoverUrl != nil ? .white : .primary)
                } else {
                    Text("Album Title")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }

                if !(artistName == "Artist") {
                    Text(artistName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(albumCoverUrl != nil ? .white : .primary)
                        .padding(.bottom, 20)
                } else {
                    Text("Artist Name")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }

                Button(action: {
                    guard !isLoading else { return }
                    isLoading = true
                    Task {
                        await suggestAlbumAsync()
                    }
                }) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "shuffle.circle")
                        }
                        Text(isLoading ? "Loading…" : "Random Album")
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                    .foregroundColor(.white)
                }
                .padding(.bottom, 20)
                .disabled(isLoading)

                if let albumMusicUrl = albumMusicUrl, let url = URL(string: "\(albumMusicUrl)") {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Open in Apple Music")
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .foregroundColor(.white)
                    }
                    .padding(.bottom, 20)
                } else {
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Open in Apple Music")
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray))
                        .foregroundColor(.white)
                        .disabled(true)
                    }
                    .padding(.bottom, 20)
                    .disabled(true)
                }


                if isSonosEnabled && isSiriEnabled {
                    Menu {
                        Button("Ask Sonos to play") { askToPlay("Sonos") }
                        Button("Ask Siri to play") { askToPlay("Siri") }
                    } label: {
                        askToPlayLabel("Ask To Play")
                    }
                } else if isSonosEnabled {
                    Button(action: { askToPlay("Sonos") }) {
                        askToPlayLabel("Ask Sonos to play")
                    }
                } else if isSiriEnabled {
                    Button(action: { askToPlay("Siri") }) {
                        askToPlayLabel("Ask Siri to play")
                    }
                }
            }
            .padding()
        }
    }

    private func askToPlay(_ service: String) {
        Speaker.shared.speak("Hey \(service), play the album \(albumTitle) by \(artistName)")
    }

    private func askToPlayLabel(_ title: String) -> some View {
        Label(title, systemImage: "speaker.wave.2.bubble")
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
            .foregroundColor(.white)
    }

    private var albumPlaceholder: some View {
        ZStack {
            Color.gray
                .frame(width: albumCoverSize, height: albumCoverSize)
            Image(systemName: "music.microphone.circle")
                .resizable()
                .scaledToFit()
                .frame(width: albumCoverSize / 3, height: albumCoverSize / 3)
                .foregroundColor(.white)
        }
    }

    @MainActor
    private func applySuggestion(_ suggestion: AlbumSuggestion) {
        self.albumTitle = suggestion.title
        self.artistName = suggestion.artist
        self.albumCoverUrl = suggestion.coverURL
        self.albumMusicUrl = suggestion.musicURL
        AlbumSuggestionService.recordSelection(title: suggestion.title, artist: suggestion.artist)
    }

    private func suggestAlbumAsync() async {
        let username = discogsUsername
        guard !username.isEmpty else {
            await MainActor.run {
                self.isLoading = false
            }
            return
        }
        do {
            let suggestion = try await AlbumSuggestionService().suggestRandomAlbum(for: username)
            await MainActor.run {
                self.applySuggestion(suggestion)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.albumCoverUrl = nil
                self.albumMusicUrl = nil
                self.isLoading = false
            }
        }
    }
        
}

struct SettingsView: View {
    @Binding var discogsUsername: String
    @Binding var isSonosEnabled: Bool
    @Binding var isSiriEnabled: Bool
    @State private var exclusionDays: Double = Double(AlbumSuggestionService.exclusionDays)

    private let cloud = NSUbiquitousKeyValueStore.default

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        Form {
            Section(header: Text("Discogs Credentials")) {
                TextField("Discogs Username", text: $discogsUsername)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: discogsUsername, initial: true) { oldValue, newValue in
                        UserDefaults.standard.set(newValue, forKey: "DiscogsUsername")
                        cloud.set(newValue, forKey: "DiscogsUsername")
                        cloud.synchronize()
                    }
            }

            Section(header: Text("Integrations"), footer: Text("Choose which voice assistants appear under the Ask To Play button. If both are off, the button is hidden.")) {
                Toggle("Sonos", isOn: $isSonosEnabled)
                    .onChange(of: isSonosEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "SonosEnabled")
                        cloud.set(newValue, forKey: "SonosEnabled")
                        cloud.synchronize()
                    }
                Toggle("Siri", isOn: $isSiriEnabled)
                    .onChange(of: isSiriEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "SiriEnabled")
                        cloud.set(newValue, forKey: "SiriEnabled")
                        cloud.synchronize()
                    }
            }

            Section(header: Text("Random Album"), footer: Text("Albums selected within this many days will be excluded from random picks. Set to 0 to allow repeats.")) {
                HStack {
                    Text("No repeat days")
                    Spacer()
                    Text("\(Int(exclusionDays))")
                        .foregroundColor(.secondary)
                }
                Slider(value: $exclusionDays, in: 0...365, step: 1)
                    .onChange(of: exclusionDays) { _, newValue in
                        AlbumSuggestionService.exclusionDays = Int(newValue)
                    }
            }

            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundColor(.secondary)
                }
                Link(destination: URL(string: "https://github.com/aanklewicz/DiscoJanice")!) {
                    HStack {
                        Text("Support")
                        Spacer()
                        Text("GitHub")
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

struct CollectionView: View {
    var discogsUsername: String
    @State private var cache: CollectionCache?
    // Sorted once when the collection loads and cached here. Previously this was a
    // computed property that re-sorted the entire collection on every access — and it
    // was read twice per row plus in the title, so rendering N albums triggered ~N full
    // sorts. Storing the result makes the list snappy regardless of collection size.
    @State private var sortedAlbums: [CachedAlbum] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private static let sortPrefixes = ["the ", "a ", "an ", "los ", "las ", "les ", "le ", "la ", "el ", "die ", "das ", "der "]

    private static func sortableArtist(_ name: String) -> String {
        let lowered = name.lowercased()
        for prefix in sortPrefixes {
            if lowered.hasPrefix(prefix) {
                return String(name.dropFirst(prefix.count))
            }
        }
        return name
    }

    /// Sorts albums by artist, ignoring leading articles. Precomputes each album's sort
    /// key once (rather than recomputing it inside every comparison) so large
    /// collections sort in a single O(n log n) pass.
    private static func sorted(_ albums: [CachedAlbum]) -> [CachedAlbum] {
        albums
            .map { (key: sortableArtist($0.artist), album: $0) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { $0.album }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let cache = cache {
                    Text("Last updated: \(cache.lastUpdated.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    List(sortedAlbums.indices, id: \.self) { index in
                        HStack {
                            Text(sortedAlbums[index].artist)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(sortedAlbums[index].title)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if isLoading {
                    Spacer()
                    ProgressView("Loading collection...")
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    Text(errorMessage)
                        .foregroundColor(.red)
                    Spacer()
                } else {
                    Spacer()
                    Text("Tap refresh to load your collection.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("Collection — \(sortedAlbums.count) item\(sortedAlbums.count == 1 ? "" : "s")")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { loadCollection() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                // Show cached data immediately if available
                let loaded = AlbumSuggestionService.loadCache()
                cache = loaded
                if let loaded {
                    sortedAlbums = Self.sorted(loaded.albums)
                } else {
                    loadCollection()
                }
            }
        }
    }

    private func loadCollection() {
        guard !discogsUsername.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await AlbumSuggestionService().forceRefresh(for: discogsUsername)
                let sorted = Self.sorted(result.albums)
                await MainActor.run {
                    cache = result
                    sortedAlbums = sorted
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

struct HistoryView: View {
    @Binding var albumTitle: String
    @Binding var artistName: String
    @Binding var albumCoverUrl: String?
    @Binding var albumMusicUrl: String?
    @Binding var selectedTab: Int
    @State private var history: [HistoryEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    VStack {
                        Spacer()
                        Text("No albums selected yet.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(history) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.artist)
                                    .fontWeight(.semibold)
                                Text(entry.title)
                                    .foregroundColor(.secondary)
                                Text(entry.selectedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            // Swipe right (leading edge) to load this album on the Album tab.
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    showOnAlbumTab(entry)
                                } label: {
                                    Label("Show", systemImage: "play.circle")
                                }
                                .tint(.accentColor)
                            }
                        }
                        // Swipe left (trailing edge) to delete, via the standard onDelete affordance.
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        AlbumSuggestionService.saveHistory([])
                        history = []
                    }) {
                        Image(systemName: "trash")
                    }
                    .disabled(history.isEmpty)
                }
            }
            .onAppear {
                history = AlbumSuggestionService.mergeHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                history = AlbumSuggestionService.mergeHistory()
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        AlbumSuggestionService.saveHistory(history)
    }

    private func showOnAlbumTab(_ entry: HistoryEntry) {
        // Show the title/artist immediately and switch to the Album tab. Use the Discogs
        // cover from the cached collection right away when we have it, then fetch the
        // Apple Music link (and iTunes art as a fallback) in the background.
        albumTitle = entry.title
        artistName = entry.artist
        let discogsCover = AlbumSuggestionService.cachedCoverImage(title: entry.title, artist: entry.artist)
        albumCoverUrl = discogsCover
        albumMusicUrl = nil
        selectedTab = 0
        Task {
            let result = await AlbumSuggestionService().lookupArtwork(title: entry.title, artist: entry.artist)
            await MainActor.run {
                if discogsCover == nil {
                    albumCoverUrl = result.coverURL
                }
                albumMusicUrl = result.musicURL
            }
        }
    }
}

#Preview {
    ContentView()
}
