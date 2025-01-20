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
    @State private var albumData: String = "Data pending"
    @State private var itemsCount: Int = 0
    @State private var randomItem: Int = 0
    @State private var pageResults: String = "Data pending"
    @State private var randomSansHundreds: Int = 0
    @State private var albumTitle: String = "Album Title"
    @State private var artistName: String = "Artist"
    @State private var albumCoverUrl: String? = nil
    @State private var albumMusicUrl: String? = nil
    @State private var isSonosEnabled: Bool = UserDefaults.standard.bool(forKey: "SonosEnabled")

    var body: some View {
        TabView {
            AlbumView(pageResults: $pageResults, albumData: $albumData, discogsUsername: discogsUsername, itemsCount: $itemsCount, randomItem: $randomItem, randomSansHundreds: $randomSansHundreds, albumTitle: $albumTitle, artistName: $artistName, albumCoverUrl: $albumCoverUrl, albumMusicUrl: $albumMusicUrl)
                .tabItem {
                    Label("Album", systemImage: "music.quarternote.3")
                }
                .disabled(discogsUsername.isEmpty)
            
            SettingsView(discogsUsername: $discogsUsername, isSonosEnabled: $isSonosEnabled)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            
//            LogView()
//                .tabItem {
//                    Label("Logs", systemImage: "tree")
//                }
            
            DebugView(albumData: $albumData, itemsCount: $itemsCount, randomItem: $randomItem, pageResults: $pageResults, albumTitle: $albumTitle, artistName: $artistName, albumCoverUrl: $albumCoverUrl)
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
        }
    }
}

struct AlbumView: View {
    @Binding var pageResults: String
    @Binding var albumData: String
    var discogsUsername: String
    @Binding var itemsCount: Int
    @Binding var randomItem: Int
    @Binding var randomSansHundreds: Int
    @Binding var albumTitle: String
    @Binding var artistName: String
    @Binding var albumCoverUrl: String?
    @Binding var albumMusicUrl: String?

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
            } else {
                Text("Album Title")
                    .font(.headline)
            }
            
            if !(artistName == "Artist") {
                Text(artistName)
                    .font(.headline)
                    .padding(.bottom, 20)
            } else {
                Text("Artist Name")
                    .font(.headline)
                    .padding(.bottom, 20)
            }
            
            Button(action: {
                fetchRandomAlbum()
            }) {
                HStack {
                    Image(systemName: "shuffle.circle")
                    Text("Random Album")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                .foregroundColor(.white)
            }
            .padding(.bottom, 20)
            
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

    func fetchRandomAlbum() {
        guard let url = URL(string: "https://api.discogs.com/users/\(discogsUsername)/collection/folders/0/releases") else {
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                return
            }

            if let jsonString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    albumData = jsonString
                }
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let pagination = json["pagination"] as? [String: Any],
                   let items = pagination["items"] as? Int {
                    DispatchQueue.main.async {
                        itemsCount = items
                        randomItem = Int.random(in: 1...items)
                        randomSansHundreds = randomItem % 100
                        fetchPageResults()
                    }
                }
            } catch {
                print("Failed to parse JSON: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }

    func fetchPageResults() {
        // Reset album cover URL and album music URL
        DispatchQueue.main.async {
            albumCoverUrl = nil
            albumMusicUrl = nil
        }

        let itemsPerPage = 100
        let page = (randomItem / itemsPerPage) + 1
        let urlString = "https://api.discogs.com/users/\(discogsUsername)/collection/folders/0/releases?page=\(page)&per_page=\(itemsPerPage)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        let taskItem = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                return
            }

            if let jsonString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    pageResults = jsonString
                }
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let releases = json["releases"] as? [[String: Any]],
                   let release = releases[randomSansHundreds]["basic_information"] as? [String: Any],
                   let title = release["title"] as? String,
                   let artists = release["artists"] as? [[String: Any]],
                   let artist = artists.first?["name"] as? String {
                    DispatchQueue.main.async {
                        albumTitle = title
                        artistName = artist.replacingOccurrences(of: " *\\([0-9]*\\)$", with: "", options: .regularExpression)
                        
                        // Fetch album cover and music URL after setting title and artist name
                        fetchAlbumCover()
                    }
                }
            } catch {
                print("Failed to parse JSON: \(error.localizedDescription)")
            }
        }
        
        taskItem.resume()
    }

    func fetchAlbumCover() {
        let sanitizedArtistName = artistName.replacingOccurrences(of: "&", with: "and")
        let sanitizedAlbumTitle = albumTitle.replacingOccurrences(of: "&", with: "and")
        let searchQuery = "\(sanitizedArtistName) \(sanitizedAlbumTitle)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlCoverString = "https://itunes.apple.com/search?term=\(searchQuery)&entity=album"

        guard let url = URL(string: urlCoverString) else {
            return
        }

        let taskCover = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstResult = results.first,
                   let artworkUrl = firstResult["artworkUrl100"] as? String,
                   let musicUrl = firstResult["collectionViewUrl"] as? String {
                    let artworkUrl300 = artworkUrl.replacingOccurrences(of: "100x100", with: "300x300")
                    DispatchQueue.main.async {
                        albumCoverUrl = artworkUrl300
                        albumMusicUrl = musicUrl
                    }
                } else {
                    DispatchQueue.main.async {
                        albumCoverUrl = nil
                        albumMusicUrl = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    albumCoverUrl = nil
                    albumMusicUrl = nil
                }
            }
        }
        
        taskCover.resume()
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

struct LogView: View {
    var body: some View {
            VStack {
                Text("Items: meow")
                }
            .padding()
    }
}

struct DebugView: View {
    @Binding var albumData: String
    @Binding var itemsCount: Int
    @Binding var randomItem: Int
    @Binding var pageResults: String
    @Binding var albumTitle: String
    @Binding var artistName: String
    @Binding var albumCoverUrl: String?

    var body: some View {
            VStack {
                Text("Items: \(itemsCount)")
                Text("Random Item: \(randomItem)")
                Text("Album Title: \(albumTitle)")
                Text("Artist: \(artistName)")
                TextField("Album Cover URL", text: Binding(
                    get: { albumCoverUrl ?? "" },
                    set: { albumCoverUrl = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                TextEditor(text: $albumData)
                    .padding()
                    .border(Color.gray, width: 1)
                TextEditor(text: $pageResults)
                    .padding()
                    .border(Color.gray, width: 1)
            }
            .padding()
    }
}

#Preview {
    ContentView()
}
