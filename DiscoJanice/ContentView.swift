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
    @State private var isSonosEnabled: Bool = UserDefaults.standard.bool(forKey: "SonosEnabled")

    var body: some View {
        TabView {
            AlbumView(discogsUsername: discogsUsername, albumTitle: $albumTitle, artistName: $artistName, albumCoverUrl: $albumCoverUrl, albumMusicUrl: $albumMusicUrl)
                .tabItem {
                    Label("Album", systemImage: "music.quarternote.3")
                }
                .disabled(discogsUsername.isEmpty)
            
            SettingsView(discogsUsername: $discogsUsername, isSonosEnabled: $isSonosEnabled)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

struct AlbumView: View {
    var discogsUsername: String
    @Binding var albumTitle: String
    @Binding var artistName: String
    @Binding var albumCoverUrl: String?
    @Binding var albumMusicUrl: String?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack {
            if let albumCoverUrl = albumCoverUrl, let url = URL(string: albumCoverUrl) {
                AsyncImage(url: url)
                    .frame(width: 300, height: 300)
                    .padding(.bottom, 20)
                    .shadow(color: .black, radius: 10, x: 0, y: 0)
            } else {
                ZStack {
                    Color.gray
                        .frame(width: 300, height: 300)
                    Image(systemName: "music.microphone.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.white)
                }
                .padding(.bottom, 20)
                .shadow(color: .black, radius: 10, x: 0, y: 0)
            }
            
            if !(albumTitle == "Album Title") {
                Text(albumTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                Text("Album Title")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            
            if !(artistName == "Artist") {
                Text(artistName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
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
            

            Menu {
                Button("Ask Sonos to play") {
                    let service = "Sonos"
                    Speaker.shared.speak("Hey \(service), play the album \(albumTitle) by \(artistName)")
                }
                Button("Ask Siri to play") {
                    let service = "Siri"
                    Speaker.shared.speak("Hey \(service), play the album \(albumTitle) by \(artistName)")
                }
            } label: {
                Label("Ask To Play", systemImage: "speaker.wave.2.bubble")
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                    .foregroundColor(.white)
            }
        }
        .padding()
    }

    @MainActor
    private func applySuggestion(_ suggestion: AlbumSuggestion) {
        self.albumTitle = suggestion.title
        self.artistName = suggestion.artist
        self.albumCoverUrl = suggestion.coverURL
        self.albumMusicUrl = suggestion.musicURL
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

    var body: some View {
        Form {
            Section(header: Text("Discogs Credentials")) {
                TextField("Discogs Username", text: $discogsUsername)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: discogsUsername, initial: true) { oldValue, newValue in
                        UserDefaults.standard.set(newValue, forKey: "DiscogsUsername")
                    }
            }
//            Section {
//                Toggle("Sonos", isOn: $isSonosEnabled)
//                    .onChange(of: isSonosEnabled, initial: true) { oldValue, newValue in
//                        UserDefaults.standard.set(newValue, forKey: "SonosEnabled")
//                    }
//            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
