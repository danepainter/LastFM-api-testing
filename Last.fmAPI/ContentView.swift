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
    @State private var username: String?
    
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if sessionKey == nil {
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
                            Button("Retry") { Task { await vm.load(user: username) } } 
                        }
                        .padding()
                    } else {
                        List(Array(vm.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(index: index + 1, track: track)
                        }
                        .listStyle(.plain)
                    }
                }
                .navigationTitle("Top Tracks")
            }
            .task { await vm.load(user: username) }
        }
        .onOpenURL { url in
            guard url.scheme == "lastfmapp",
                  url.host == "auth",
                  let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "token" })?.value else { return }
            Task {
                do {
                    let session = try await auth.fetchSession(token: token)
                    sessionKey = session.key
                    username = session.name
                    await vm.load(user: session.name)
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
