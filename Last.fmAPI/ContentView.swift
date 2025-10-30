//
//  ContentView.swift
//  Last.fmAPI
//
//  Created by Dane Shaw on 10/29/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = TracksViewModel()


    var body: some View {
        NavigationStack {
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
}

#Preview {
    ContentView()
}
