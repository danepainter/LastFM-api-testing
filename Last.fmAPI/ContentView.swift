//
//  ContentView.swift
//  Last.fmAPI
//
//  Created by Dane Shaw on 10/29/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = TracksViewModel()
    @Environment(\.openURL) private var openURL
    private let auth = AuthService()
    @State private var sessionKey: String?
    
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let sk = sessionKey {
                    Text("Connected: \(sk)").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Connect Last.fm") {
                        let url = auth.makeAuthURL()
                        openURL(url)
                    }
                }
                
                Group {
                    if vm.isLoading {
                        ProgressView("Loading...")
                    } else if let message = vm.errorMessage {
                        VStack(spacing: 12) {
                            Text("Oops").font(.headline)
                            Text(message).font(.subheadline).foregroundStyle(.secondary)
                            Button("Retry") { Task { await vm.load() } } 
                        }
                        .padding()
                    } else {
                        List(vm.tracks) { track in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.name).font(.headline)
                                if let artist = track.artist?.name {
                                    Text(artist).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .navigationTitle("Top Tracks")
            }
            .task { await vm.load() }
        }
        .onOpenURL { url in
            guard url.scheme == "lastfmapp",
                  url.host == "auth",
                  let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "token" })?.value else { return }
            Task {
                do {
                    let sk = try await auth.fetchSessionKey(token: token)
                    sessionKey = sk
                } catch {
                    print("Failed to fetch session:", error)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
