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
    @State private var selectedRange: RangeOption = .overall
    
    
    var body: some View {
        NavigationStack {
            if sessionKey == nil {
                VStack(spacing: 24) {
                    Spacer()
                    Text("SFLHC \n Music Tracking ")
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .bold()
                    Button {
                        let url = auth.makeAuthURL()
                        openURL(url)
                    } label: {
                        Text("Connect to Last.fm")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                    Spacer()
                }
            } else {
                List {
                    Section {
                        // Controls row
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Time Range", selection: $selectedRange) {
                                ForEach(RangeOption.allCases, id: \.self) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        // Content rows
                        if vm.isLoading {
                            ProgressView("Loading...")
                        } else if let message = vm.errorMessage {
                            VStack(spacing: 12) {
                                Text("Oops").font(.headline)
                                Text(message).font(.subheadline).foregroundStyle(.secondary)
                                Button("Retry") { Task { await vm.load(user: username, period: selectedRange.apiValue) } }
                            }
                            .padding(.vertical, 8)
                        } else {
                            // Fixed-height, scrollable container showing ~5 rows
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(vm.tracks.enumerated()), id: \.element.id) { index, track in
                                        TrackRow(index: index + 1, track: track)
                                            .padding(.vertical, 8)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 340)
                            // keep default List section horizontal insets by padding internally
                        }
                    }
                }
                .navigationTitle("Your Top Tracks")
                .navigationBarTitleDisplayMode(.inline)
                .task { await vm.load(user: username, period: selectedRange.apiValue) }
                .onChange(of: selectedRange) { _, _ in
                    Task { await vm.load(user: username, period: selectedRange.apiValue) }
                }
            }
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

// MARK: - Time Range Options
enum RangeOption: CaseIterable, Hashable {
    case oneDay
    case sevenDays
    case oneMonth
    case sixMonths
    case oneYear
    case overall

    var title: String {
        switch self {
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .oneMonth: return "1 month"
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        case .overall: return "All Time"
        }
    }

    // Last.fm supported periods: overall, 7day, 1month, 3month, 6month, 12month
    // There is no 1-day top tracks; we approximate by using 7day.
    var apiValue: String? {
        switch self {
        case .oneDay: return "7day"
        case .sevenDays: return "7day"
        case .oneMonth: return "1month"
        case .sixMonths: return "6month"
        case .oneYear: return "12month"
        case .overall: return "overall"
        }
    }
}

#Preview {
    ContentView()
}
