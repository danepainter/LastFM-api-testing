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
    @StateObject private var listeningActivityVM = ListeningActivityChartViewModel()
    @Environment(\.openURL) private var openURL
    private let auth = AuthService()
    @State private var sessionKey: String?
    @State private var username: String?
    @State private var selectedRange: RangeOption = .overall
    // Chart-specific range selector (independent of track fetch range)
    @State private var chartRange: RangeOption = .sevenDays
    @State private var activityRange: RangeOption = .sevenDays
    // Grid-specific range selector (excludes 1 day)
    @State private var gridRange: RangeOption = .sevenDays
    @StateObject private var gridVM = TracksViewModel()
    @StateObject private var gridImageGenerator = GridImageGenerator()
    @State private var selectedGridSize: GridSize = .threeByThree
    @State private var selectedExportRange: ExportDateRange = .sevenDays
    @State private var showSaveSuccess = false
    @State private var saveError: String?
    private let chartOptions: [RangeOption] = [.oneDay, .sevenDays, .oneMonth, .threeMonths, .sixMonths]
    private let activityChartOptions: [RangeOption] = [.oneDay, .sevenDays, .oneMonth, .threeMonths, .sixMonths, .oneYear, .overall]
    private let gridOptions: [RangeOption] = [.sevenDays, .oneMonth, .threeMonths, .sixMonths, .oneYear, .overall]
    
    
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
        case threeMonths
        case sixMonths
        case oneYear
        case overall

        var title: String {
            switch self {
            case .oneDay: return "1 day"
            case .sevenDays: return "7 days"
            case .oneMonth: return "1 month"
            case .threeMonths: return "3 months"
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
            case .threeMonths: return "3month"
            case .sixMonths: return "6month"
            case .oneYear: return "12month"
            case .overall: return "overall"
            }
        }
        
        var dayStride: Int {
            switch self {
            case .oneDay: return 1
            case .sevenDays: return 1
            case .oneMonth: return 3
            case .threeMonths: return 5
            case .sixMonths: return 7
            case .oneYear: return 30
            case .overall: return 90
            }
        }
        
        var maxPagesForActivity: Int {
            switch self {
            case .oneDay: return 5        // ~1000 scrobbles max
            case .sevenDays: return 10     // ~2000 scrobbles max
            case .oneMonth: return 20     // ~4000 scrobbles max
            case .threeMonths: return 30   // ~6000 scrobbles max
            case .sixMonths: return 50    // ~10,000 scrobbles max
            case .oneYear: return 100     // ~20,000 scrobbles max
            case .overall: return 250     // ~50,000 scrobbles max (covers 3 years at ~45 scrobbles/day)
            }
        }
        
        var aggregationUnit: Calendar.Component {
            switch self {
            case .oneDay, .sevenDays, .oneMonth:
                // Short ranges: show daily granularity
                return .day
            case .threeMonths:
                // Medium range: aggregate by week to avoid overcrowding (~13 points)
                return .weekOfYear
            case .sixMonths:
                // Medium range: aggregate by week to avoid overcrowding (~26 points)
                return .weekOfYear
            case .oneYear:
                // Longer range: aggregate by week (~52 points)
                return .weekOfYear
            case .overall:
                // Very long range: aggregate by month to keep chart readable (~36 points for 3 years)
                return .month
            }
        }
        
        var desiredAxisLabelCount: Int {
            switch self {
            case .oneDay: return 12      // Show every ~2 hours
            case .sevenDays: return 7     // Show each day
            case .oneMonth: return 10     // Show ~every 3 days
            case .threeMonths: return 12   // Show ~every week
            case .sixMonths: return 12    // Show ~every 2 weeks
            case .oneYear: return 12      // Show ~every month
            case .overall: return 12      // Show ~every 3 months
            }
        }
        
        var xAxisFormat: Date.FormatStyle {
            switch self {
            case .oneDay:
                return .dateTime.hour().minute()
            case .sevenDays:
                return .dateTime.weekday(.abbreviated)
            case .oneMonth:
                return .dateTime.month(.abbreviated).day()
            case .threeMonths:
                return .dateTime.month(.abbreviated).day()
            case .sixMonths:
                return .dateTime.month(.abbreviated)
            case .oneYear:
                return .dateTime.month(.abbreviated)
            case .overall:
                return .dateTime.month(.abbreviated).year(.twoDigits)
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
                    .foregroundStyle(Color.primaryRed)
                Button {
                    let url = auth.makeAuthURL()
                    openURL(url)
                } label: {
                    Text("Connect to Last.fm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.primaryRed)
                .controlSize(.large)
                .padding(.horizontal, 24)
                Spacer()
            }
            .background(Color.darkestBackground)
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
                                .buttonStyle(.borderedProminent)
                                .tint(Color.primaryRed)
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
                    artworkGridSection()
                    exportGridSection()
                    genreChartSection()
                    dailyActivitySection()
                }
            }
            .navigationTitle("Your Top Tracks")
            .navigationBarTitleDisplayMode(.inline)
                                .tint(Color.primaryRed)
            .task { 
                await vm.load(user: username, period: selectedRange.apiValue)
                await buildDailyActivity(for: activityRange)
            }
            .onChange(of: selectedRange) { _, _ in
                Task { await vm.load(user: username, period: selectedRange.apiValue) }
            }
            .onReceive(vm.$tracks) { _ in
                Task {
                    ggvm.maxTagsPerTrack = 3
                    await buildChart(for: chartRange)
                    await buildDailyActivity(for: activityRange)
                }
            }
            .onChange(of: chartRange) { _, newValue in
                Task { await buildChart(for: newValue) }
            }
            .onChange(of: activityRange) { _, newValue in
                Task { await buildDailyActivity(for: newValue) }
            }
        }

        @ViewBuilder
        fileprivate func artworkGridSection() -> some View {
            Section("Top Track Artwork") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Time Range", selection: $gridRange) {
                        ForEach(gridOptions, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if gridVM.isLoading {
                        ProgressView("Loading artwork...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if let message = gridVM.errorMessage {
                        VStack(spacing: 12) {
                            Text("Unable to load artwork")
                                .font(.headline)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task {
                                    await gridVM.load(user: username, period: gridRange.apiValue)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.primaryRed)
                        }
                        .padding(.vertical, 8)
                    } else if gridVM.tracks.isEmpty {
                        Text("No tracks available for this range.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        let columns = [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ]
                        
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(gridVM.tracks, id: \.id) { track in
                                    TrackArtworkView(track: track)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(height: 500)
                    }
                }
            }
            .task {
                await gridVM.load(user: username, period: gridRange.apiValue, limit: 50)
            }
            .onChange(of: gridRange) { _, newValue in
                Task {
                    await gridVM.load(user: username, period: newValue.apiValue, limit: 50)
                }
            }
        }
        
        @ViewBuilder
        fileprivate func exportGridSection() -> some View {
            Section("Export Grid Image") {
                VStack(alignment: .leading, spacing: 16) {
                    // Size picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Grid Size")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Grid Size", selection: $selectedGridSize) {
                            ForEach(GridSize.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Date range picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date Range")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Date Range", selection: $selectedExportRange) {
                            ForEach(ExportDateRange.allCases) { range in
                                Text(range.displayTitle).tag(range)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // Preview info
                    let neededTracks = selectedGridSize.totalImages
                    Text("Will generate \(selectedGridSize.title) grid (\(neededTracks) tracks) for \(selectedExportRange.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Loading indicator section (always visible when generating)
                    if gridImageGenerator.isGeneratingImage {
                        HStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.primaryRed)
                                .scaleEffect(1.2)
                            Text("Generating grid image...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    
                    // Progress bar (visible during generation)
                    if gridImageGenerator.isGeneratingImage && gridImageGenerator.generationProgress > 0 {
                        VStack(spacing: 4) {
                            ProgressView(value: gridImageGenerator.generationProgress)
                                .progressViewStyle(.linear)
                                .tint(Color.primaryRed)
                            Text("\(Int(gridImageGenerator.generationProgress * 100))% complete")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Generate and save button
                    Button {
                        Task {
                            await generateAndSaveGrid()
                        }
                    } label: {
                        HStack {
                            if gridImageGenerator.isGeneratingImage {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text(gridImageGenerator.isGeneratingImage ? "Generating & Saving..." : "Generate & Save to Photos")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.primaryRed)
                    .disabled(gridImageGenerator.isGeneratingImage || gridImageGenerator.isLoading)
                    
                    // Error message
                    if let error = saveError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryRed)
                    }
                    
                    // Success message
                    if showSaveSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.primaryRed)
                            Text("Saved to Photos!")
                                .font(.caption)
                                .foregroundStyle(Color.primaryRed)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: selectedExportRange) { _, newValue in
                Task {
                    let limit = selectedGridSize.totalImages + 10 // Fetch a few extra in case some tracks don't have images
                    await gridImageGenerator.loadTracks(user: username, dateRange: newValue, limit: limit)
                }
            }
            .onChange(of: selectedGridSize) { _, newValue in
                Task {
                    let limit = newValue.totalImages + 10
                    await gridImageGenerator.loadTracks(user: username, dateRange: selectedExportRange, limit: limit)
                }
            }
            .task {
                let limit = selectedGridSize.totalImages + 10
                await gridImageGenerator.loadTracks(user: username, dateRange: selectedExportRange, limit: limit)
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
        
        @ViewBuilder
        fileprivate func dailyActivitySection() -> some View {
            Section("Listening Activity") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Time Range", selection: $activityRange) {
                        ForEach(activityChartOptions, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if listeningActivityVM.isLoading {
                        ProgressView("Loading activity…")
                    } else if let error = listeningActivityVM.errorMessage {
                        VStack(spacing: 8) {
                            Text("Unable to load activity")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else if listeningActivityVM.points.isEmpty {
                        Text("No activity data available for this range.")
                            .foregroundStyle(.secondary)
                    } else {
                        let timeUnit: Calendar.Component = activityRange.aggregationUnit
                        let chartUnit: Calendar.Component = {
                            switch timeUnit {
                            case .day: return .day
                            case .weekOfYear: return .weekOfYear
                            case .month: return .month
                            default: return .day
                            }
                        }()
                        
                        Chart(listeningActivityVM.points) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: chartUnit),
                                y: .value("Plays", point.playCount)
                            )
                            .foregroundStyle(Color.primaryRed.gradient)
                            .interpolationMethod(.catmullRom)
                            .symbol(Circle().strokeBorder(lineWidth: 2))
                            
                            AreaMark(
                                x: .value("Date", point.date, unit: chartUnit),
                                y: .value("Plays", point.playCount)
                            )
                            .foregroundStyle(Color.primaryRed.opacity(0.15).gradient)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: activityRange.desiredAxisLabelCount)) { value in
                                AxisGridLine()
                                if let date = value.as(Date.self) {
                                    AxisValueLabel {
                                        Text(date, format: activityRange.xAxisFormat)
                                            .font(.caption2)
                                            .rotationEffect(.degrees(-90))
                                            .frame(width: 20, height: 40)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 200)
                        
                        let totalPlays = listeningActivityVM.points.reduce(0) { $0 + $1.playCount }
                        let avgPlays = listeningActivityVM.points.isEmpty ? 0 : totalPlays / listeningActivityVM.points.count
                        
                        let periodLabel: String = {
                            switch activityRange.aggregationUnit {
                            case .day: return "per day"
                            case .weekOfYear: return "per week"
                            case .month: return "per month"
                            default: return "per day"
                            }
                        }()
                        
                        Text("Total: \(totalPlays) plays • Average: \(avgPlays) \(periodLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            case .threeMonths:
                start = cal.date(byAdding: .month, value: -3, to: end) ?? end
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
            case .threeMonths:
                return (.weekOfYear, 1)
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
            case .threeMonths: return (.month, 1)
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
            case .threeMonths:
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
        
        func buildDailyActivity(for option: RangeOption) async {
            guard let user = username, !user.isEmpty,
                  let interval = makeInterval(for: option) else { return }
            // Use higher page limits for longer time ranges
            let maxPages = option.maxPagesForActivity
            // Use appropriate aggregation unit to prevent overcrowding
            let aggregationUnit = option.aggregationUnit
            await listeningActivityVM.load(user: user, in: interval, maxPages: maxPages, aggregationUnit: aggregationUnit)
        }
        
        func generateAndSaveGrid() async {
            saveError = nil
            showSaveSuccess = false
            
            // Ensure loading state is visible
            gridImageGenerator.isGeneratingImage = true
            
            // Update progress to show we're starting
            await MainActor.run {
                gridImageGenerator.generationProgress = 0.0
            }
            
            guard let image = await gridImageGenerator.generateGridImage(
                size: selectedGridSize,
                dateRange: selectedExportRange,
                username: username
            ) else {
                gridImageGenerator.isGeneratingImage = false
                saveError = "Failed to generate grid image. Make sure you have enough tracks with artwork."
                return
            }
            
            // Update progress to show we're saving
            await MainActor.run {
                gridImageGenerator.generationProgress = 0.98
            }
            
            do {
                try await gridImageGenerator.saveToPhotoLibrary(image)
                await MainActor.run {
                    gridImageGenerator.isGeneratingImage = false
                    gridImageGenerator.generationProgress = 0.0
                }
                showSaveSuccess = true
                // Hide success message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showSaveSuccess = false
            } catch {
                await MainActor.run {
                    gridImageGenerator.isGeneratingImage = false
                    gridImageGenerator.generationProgress = 0.0
                }
                saveError = error.localizedDescription
            }
        }
    }   
    





#Preview {
    ContentView()
}
