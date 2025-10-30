//
//  ContentView.swift
//  Last.fmAPI
//
//  Created by Dane Shaw on 10/29/25.
//

import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var vm = TracksViewModel()
    @StateObject private var ggvm = GenreStackedAreaChartViewModel()
    @Environment(\.openURL) private var openURL
    private let auth = AuthService()
    @State private var sessionKey: String?
    @State private var username: String?
    @State private var selectedRange: RangeOption = .overall
    // Chart-specific range selector (independent of track fetch range)
    @State private var chartRange: RangeOption = .sevenDays
    private let chartOptions: [RangeOption] = [.oneDay, .sevenDays, .oneMonth, .sixMonths]
    
    
    var body: some View {
        NavigationStack {
            if sessionKey == nil {
                loginView()
            } else {
                tracksListView()
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

    // MARK: - Subviews
        @ViewBuilder
        fileprivate func loginView() -> some View {
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
        }

        @ViewBuilder
        fileprivate func tracksListView() -> some View {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Time Range", selection: $selectedRange) {
                            ForEach(RangeOption.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }

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
                    }
                }

                if !vm.tracks.isEmpty {
                    genreChartSection()
                }
            }
            .navigationTitle("Your Top Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load(user: username, period: selectedRange.apiValue) }
            .onChange(of: selectedRange) { _, _ in
                Task { await vm.load(user: username, period: selectedRange.apiValue) }
            }
            .onReceive(vm.$tracks) { _ in
                Task {
                    ggvm.maxTagsPerTrack = 3
                    await buildChart(for: chartRange)
                }
            }
            .onChange(of: chartRange) { _, newValue in
                Task { await buildChart(for: newValue) }
            }
        }

        @ViewBuilder
        fileprivate func genreChartSection() -> some View {
            Section("Listening Time by Genre") {
                VStack(alignment: .leading, spacing: 12) {
                    // Chart-specific date selector
                    Picker("Chart Range", selection: $chartRange) {
                        ForEach(chartOptions, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Donut chart uses totals per genre for the selected window
                    let totals = ggvm.totals
                    if ggvm.isLoading {
                        ProgressView("Building chart…")
                    } else if totals.isEmpty {
                        Text("No genre data available for this range.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(totals) { total in
                            SectorMark(
                                angle: .value("Seconds", total.totalSeconds),
                                innerRadius: .ratio(0.6),
                                angularInset: 1
                            )
                            .foregroundStyle(by: .value("Genre", total.genre))
                        }
                        .chartForegroundStyleScale(
                            domain: ggvm.orderedGenres,
                            range: ggvm.orderedGenres.map { ggvm.color(for: $0) }
                        )
                        .chartLegend(position: .bottom, spacing: 8)
                        .frame(height: 220)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ggvm.totals) { total in
                                let hours = total.totalSeconds / 3600.0
                                Label("\(total.genre.capitalized): \(hours, specifier: "%.1f")h", systemImage: "music.note.list")
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
    

    // MARK: - Helpers
        func buildChart(for option: RangeOption) async {
            guard let interval = makeInterval(for: option) else { return }
            let bucket = chooseBucket(for: option)
            if let user = username, !user.isEmpty {
                // Prefer recent scrobbles for all ranges; build() will fallback using provided tracks when needed
                await ggvm.buildFromRecent(
                    user: user,
                    in: interval,
                    bucketComponent: bucket.component,
                    bucketStep: bucket.step,
                    calendar: .current,
                    fallbackTracks: vm.tracks
                )
            } else {
                await ggvm.build(
                    from: vm.tracks,
                    in: interval,
                    bucketComponent: bucket.component,
                    bucketStep: bucket.step
                )
            }
        }
        func makeInterval(for option: RangeOption) -> DateInterval? {
            let cal = Calendar.current
            let end = Date()
            let start: Date
            switch option {
            case .oneDay:
                start = cal.date(byAdding: .day, value: -1, to: end) ?? end
            case .sevenDays:
                start = cal.date(byAdding: .day, value: -7, to: end) ?? end
            case .oneMonth:
                start = cal.date(byAdding: .month, value: -1, to: end) ?? end
            case .sixMonths:
                start = cal.date(byAdding: .month, value: -6, to: end) ?? end
            case .oneYear:
                start = cal.date(byAdding: .year, value: -1, to: end) ?? end
            case .overall:
                start = cal.date(byAdding: .year, value: -3, to: end) ?? end
            }
            return DateInterval(start: start, end: end)
        }

        func chooseBucket(for option: RangeOption) -> (component: Calendar.Component, step: Int) {
            switch option {
            case .oneDay:
                // 12 points across 24 hours -> every 2 hours
                return (.hour, 2)
            case .sevenDays:
                // 14 points across 7 days -> every 12 hours
                return (.hour, 12)
            case .oneMonth:
                return (.day, 1)
            case .sixMonths:
                return (.weekOfYear, 1)
            case .oneYear:
                return (.month, 1)
            case .overall:
                return (.month, 1)
            }
        }

        // MARK: - Axis helpers
        func xAxisStride(for option: RangeOption) -> (component: Calendar.Component, count: Int) {
            switch option {
            case .oneDay: return (.hour, 2)
            case .sevenDays: return (.day, 1)
            case .oneMonth: return (.day, 7)
            case .sixMonths: return (.month, 1)
            case .oneYear: return (.month, 1)
            case .overall: return (.month, 3)
            }
        }

        func xAxisDateFormatter(for option: RangeOption) -> DateFormatter {
            let f = DateFormatter()
            f.locale = .current
            switch option {
            case .oneDay:
                f.dateFormat = "ha" // 2 PM
            case .sevenDays:
                f.dateFormat = "E" // Mon, Tue
            case .oneMonth:
                f.dateFormat = "MMM d" // Jan 5
            case .sixMonths:
                f.dateFormat = "MMM" // Jan
            case .oneYear:
                f.dateFormat = "MMM" // Jan
            case .overall:
                f.dateFormat = "MMM yy" // Jan 25
            }
            return f
        }
    }   
    





#Preview {
    ContentView()
}
