import Foundation
import Combine
import SwiftUI

@MainActor
final class GenreStackedAreaChartViewModel: ObservableObject {
    struct GenreChartPoint: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let genre: String
        let seconds: Double
    }

    struct GenreTotal: Identifiable, Hashable {
        let id = UUID()
        let genre: String
        let totalSeconds: Double
    }

    @Published var isLoading = false
    @Published var errorMessage: String?

    // Flattened points: X = date bucket start, Y = seconds, series/color = genre.
    @Published var points: [GenreChartPoint] = []

    // Totals per genre across the provided dataset (useful for legends/summary).
    @Published var totals: [GenreTotal] = []

    // X-axis tick positions (bucket boundaries)
    @Published var bucketStarts: [Date] = []

    // Stable ordering for stacked rendering (top genres first, then "other")
    @Published var orderedGenres: [String] = []

    // Controls
    var maxTagsPerTrack: Int = 1
    private let api = APIClient()
    // Cache metadata per unique track to avoid re-fetching across buckets and builds
    private var metaCache: [String: (durationSec: Double, tags: [String])] = [:]
    private let topGenreCount: Int = 7

    /// Build chart data across a time window using uniform distribution of listening time
    /// per track across time buckets. Listening time is approximated as (playcount * duration).
    func build(
        from tracks: [Track],
        in window: DateInterval,
        bucketComponent: Calendar.Component = .day,
        bucketStep: Int = 1,
        calendar: Calendar = .current
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 1) Make bucket boundaries (inclusive starts)
        let starts = Self.makeBucketStarts(in: window, component: bucketComponent, step: bucketStep, calendar: calendar)
        guard starts.count > 0 else {
            self.points = []
            self.totals = []
            self.bucketStarts = []
            return
        }

        // 2) Concurrently fetch per-track duration and tags
        struct TrackMeta { let durationSec: Double; let tags: [String] }
        var perBucketGenreSeconds: [Date: [String: Double]] = [:]
        var genreTotalsSeconds: [String: Double] = [:]
        let bucketCount = starts.count

        // Check cache first to avoid unnecessary API calls
        let cacheKeyPrefix = "\(maxTagsPerTrack)_"
        
        await withTaskGroup(of: (Int, TrackMeta?).self) { group in
            for (idx, track) in tracks.enumerated() {
                let artistName = track.artist?.name ?? ""
                let trackName = track.name
                let playcount = Double(track.playcount ?? "0") ?? 0
                let cacheKey = "\(cacheKeyPrefix)\(artistName)|\(trackName)"
                
                group.addTask { [weak self] in
                    guard let self = self else { return (idx, nil) }
                    
                    // Check cache first (synchronous read is safe)
                    if let cached = await self.metaCache[cacheKey] {
                        let totalSeconds = cached.durationSec * playcount
                        return (idx, TrackMeta(durationSec: totalSeconds, tags: cached.tags))
                    }
                    
                    if let meta = await Self.fetchTrackMeta(artist: artistName, track: trackName, tagLimit: self.maxTagsPerTrack) {
                        // Cache the result on main actor
                        await MainActor.run {
                            self.metaCache[cacheKey] = (durationSec: meta.durationSec, tags: meta.tags)
                        }
                        let totalSeconds = meta.durationSec * playcount
                        return (idx, TrackMeta(durationSec: totalSeconds, tags: meta.tags))
                    } else {
                        return (idx, nil)
                    }
                }
            }

            for await (_, metaOpt) in group {
                guard let meta = metaOpt, meta.durationSec > 0, !meta.tags.isEmpty else { continue }
                let tags = meta.tags
                let secondsPerTag = meta.durationSec / Double(tags.count)
                let secondsPerBucket = meta.durationSec / Double(bucketCount)

                // Distribute uniformly across buckets and split across tags
                for start in starts {
                    let perTagShare = secondsPerBucket / Double(tags.count)
                    for tag in tags {
                        var genreMap = perBucketGenreSeconds[start] ?? [:]
                        genreMap[tag, default: 0] += perTagShare
                        perBucketGenreSeconds[start] = genreMap
                    }
                }

                for tag in tags {
                    genreTotalsSeconds[tag, default: 0] += secondsPerTag
                }
            }
        }

        // 3) Determine top N genres by total seconds; everything else is "other"
        let sortedTotalsPairs = genreTotalsSeconds.sorted { $0.value > $1.value }
        let topN = Set(sortedTotalsPairs.prefix(topGenreCount).map { $0.key })

        // 4) Re-aggregate per-bucket values into mapped genres (top 4 + other)
        var bucketMapped: [Date: [String: Double]] = [:]
        for start in starts {
            guard let genreMap = perBucketGenreSeconds[start] else { continue }
            var mapped: [String: Double] = [:]
            for (genre, secs) in genreMap {
                let key = topN.contains(genre) ? genre : "other"
                mapped[key, default: 0] += secs
            }
            bucketMapped[start] = mapped
        }

        // 5) Flatten mapped buckets to points
        var built: [GenreChartPoint] = []
        for start in starts {
            if let map = bucketMapped[start] {
                for (genre, secs) in map where secs > 0 {
                    built.append(GenreChartPoint(date: start, genre: genre, seconds: secs))
                }
            }
        }

        built.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.genre != b.genre { return a.genre < b.genre }
            return a.seconds < b.seconds
        }

        // 6) Recompute totals with the same mapping
        var totalsMapped: [String: Double] = [:]
        for (genre, secs) in genreTotalsSeconds {
            let key = topN.contains(genre) ? genre : "other"
            totalsMapped[key, default: 0] += secs
        }

        // Keep top-N ordering, then "other" if present and not already included
        var totalsArray: [GenreTotal] = []
        let topInOrder = sortedTotalsPairs.prefix(topGenreCount).map { $0.key }
        for key in topInOrder {
            if let secs = totalsMapped[key], secs > 0 { totalsArray.append(GenreTotal(genre: key, totalSeconds: secs)) }
        }
        if !topInOrder.contains("other"), let otherSecs = totalsMapped["other"], otherSecs > 0 {
            totalsArray.append(GenreTotal(genre: "other", totalSeconds: otherSecs))
        }

        self.points = built
        self.totals = totalsArray
        self.bucketStarts = starts
        // Update stable stacking order for rendering
        var order = topInOrder
        if (totalsMapped["other"].map({ $0 > 0 }) ?? false) && !order.contains("other") { order.append("other") }
        self.orderedGenres = order
    }

    /// Build chart data from recent scrobbles (assigns each track's duration entirely to its play bucket)
    func buildFromRecent(
        user: String,
        in window: DateInterval,
        bucketComponent: Calendar.Component = .day,
        bucketStep: Int = 1,
        calendar: Calendar = .current,
        fallbackTracks: [Track]? = nil
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let starts = Self.makeBucketStarts(in: window, component: bucketComponent, step: bucketStep, calendar: calendar)
        guard starts.count > 0 else {
            self.points = []
            self.totals = []
            self.bucketStarts = []
            return
        }

        // Fetch recent tracks in the window
        let recent: [RecentTrack]
        do {
            // Use paginated fetch to ensure we cover the entire window
            recent = try await api.fetchUserRecentTracksAll(user: user, from: window.start, to: window.end, pageSize: 200, maxPages: 10)
        } catch {
            self.errorMessage = error.localizedDescription
            self.points = []
            self.totals = []
            self.bucketStarts = starts
            return
        }

        // Strictly filter by window and drop entries without a timestamp (e.g., nowplaying)
        let filtered: [(date: Date, track: RecentTrack)] = recent.compactMap { rt in
            guard let uts = Double(rt.uts) else { return nil }
            let d = Date(timeIntervalSince1970: uts)
            return (d >= window.start && d < window.end) ? (d, rt) : nil
        }

        if filtered.isEmpty {
            if let fallback = fallbackTracks, !fallback.isEmpty {
                await self.build(from: fallback, in: window, bucketComponent: bucketComponent, bucketStep: bucketStep, calendar: calendar)
                return
            }
            self.points = []
            self.totals = []
            self.bucketStarts = starts
            return
        }

        // Aggregate plays by bucket and unique track, so we fetch metadata once per track
        struct TrackKey: Hashable { let artist: String; let track: String }
        func cacheKey(_ k: TrackKey) -> String { (k.artist.lowercased() + "\u{1F}" + k.track.lowercased()) }

        var playsByBucket: [Date: [TrackKey: Int]] = [:]
        var unique: Set<TrackKey> = []
        for (playDate, scrobble) in filtered {
            let artistName = scrobble.artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trackName = scrobble.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artistName.isEmpty, !trackName.isEmpty else { continue }
            let key = TrackKey(artist: artistName, track: trackName)
            let bucketStart = starts.last(where: { $0 <= playDate }) ?? starts.first!
            var map = playsByBucket[bucketStart] ?? [:]
            map[key, default: 0] += 1
            playsByBucket[bucketStart] = map
            unique.insert(key)
        }

        // Fetch missing metadata in parallel (respect cache)
        var toFetch: [TrackKey] = []
        for k in unique { if metaCache[cacheKey(k)] == nil { toFetch.append(k) } }
        if !toFetch.isEmpty {
            await withTaskGroup(of: (String, (Double, [String]))?.self) { group in
                for k in toFetch {
                    group.addTask { [maxTagsPerTrack] in
                        if let meta = await Self.fetchTrackMeta(artist: k.artist, track: k.track, tagLimit: maxTagsPerTrack) {
                            return await (cacheKey(k), (meta.durationSec, meta.tags))
                        } else {
                            return await (cacheKey(k), (180.0, []))
                        }
                    }
                }
                for await res in group {
                    if let (key, value) = res { metaCache[key] = value }
                }
            }
        }

        // Build seconds by bucket and genre using cached metadata
        var perBucketGenreSeconds: [Date: [String: Double]] = [:]
        var genreTotalsSeconds: [String: Double] = [:]
        for start in starts {
            guard let map = playsByBucket[start] else { continue }
            for (k, count) in map {
                let (duration, tagsRaw) = metaCache[cacheKey(k)] ?? (180.0, [])
                let totalSec = duration * Double(count)
                let tags = tagsRaw.isEmpty ? ["other"] : tagsRaw
                let perTag = totalSec / Double(tags.count)
                for tag in tags {
                    var g = perBucketGenreSeconds[start] ?? [:]
                    g[tag, default: 0] += perTag
                    perBucketGenreSeconds[start] = g
                    genreTotalsSeconds[tag, default: 0] += perTag
                }
            }
        }

        // If no per-bucket data could be built (e.g., all scrobbles out of window), fallback
        if perBucketGenreSeconds.isEmpty {
            if let fallback = fallbackTracks, !fallback.isEmpty {
                await self.build(from: fallback, in: window, bucketComponent: bucketComponent, bucketStep: bucketStep, calendar: calendar)
                return
            }
            self.points = []
            self.totals = []
            self.bucketStarts = starts
            return
        }

        // Determine top N and map others
        let sortedTotalsPairs = genreTotalsSeconds.sorted { $0.value > $1.value }
        let topN = Set(sortedTotalsPairs.prefix(topGenreCount).map { $0.key })

        var bucketMapped: [Date: [String: Double]] = [:]
        for start in starts {
            let genreMap = perBucketGenreSeconds[start] ?? [:]
            var mapped: [String: Double] = [:]
            for (genre, secs) in genreMap {
                let key = topN.contains(genre) ? genre : "other"
                mapped[key, default: 0] += secs
            }
            bucketMapped[start] = mapped
        }

        var built: [GenreChartPoint] = []
        for start in starts {
            if let map = bucketMapped[start] {
                for (genre, secs) in map where secs > 0 {
                    built.append(GenreChartPoint(date: start, genre: genre, seconds: secs))
                }
            }
        }
        built.sort { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.genre != b.genre { return a.genre < b.genre }
            return a.seconds < b.seconds
        }

        var totalsMapped: [String: Double] = [:]
        for (genre, secs) in genreTotalsSeconds {
            let key = topN.contains(genre) ? genre : "other"
            totalsMapped[key, default: 0] += secs
        }
        var totalsArray: [GenreTotal] = []
        let topInOrder = sortedTotalsPairs.prefix(topGenreCount).map { $0.key }
        for key in topInOrder {
            if let secs = totalsMapped[key], secs > 0 { totalsArray.append(GenreTotal(genre: key, totalSeconds: secs)) }
        }
        if !topInOrder.contains("other"), let otherSecs = totalsMapped["other"], otherSecs > 0 {
            totalsArray.append(GenreTotal(genre: "other", totalSeconds: otherSecs))
        }

        self.points = built
        self.totals = totalsArray
        self.bucketStarts = starts
        var order = topInOrder
        if (totalsMapped["other"].map({ $0 > 0 }) ?? false) && !order.contains("other") { order.append("other") }
        self.orderedGenres = order
    }

    // MARK: - Styling helpers
    func color(for genre: String) -> Color {
        // Use distinct colors for common genres - mix of Cherry Chaos and other vibrant colors
        let palette: [String: Color] = [
            "rock": Color.primaryRed,                    // Cherry Chaos red
            "pop": Color.blue,                            // Blue
            "hip-hop": Color.purple,                     // Purple
            "electronic": Color.teal,                    // Teal
            "indie": Color.orange,                        // Orange
            "metal": Color.gray,                          // Gray
            "jazz": Color.green,                          // Green
            "classical": Color.brown,                     // Brown
            "r&b": Color.pink,                           // Pink
            "country": Color(red: 0.85, green: 0.65, blue: 0.13), // Gold
            "folk": Color(red: 0.55, green: 0.8, blue: 0.5),    // Light green
            "reggae": Color(red: 1.0, green: 0.84, blue: 0.0),  // Yellow
            "blues": Color(red: 0.0, green: 0.5, blue: 1.0),     // Royal blue
            "alternative": Color(red: 0.75, green: 0.0, blue: 0.75), // Magenta
            "punk": Color(red: 1.0, green: 0.0, blue: 0.5),      // Hot pink
            "soul": Color(red: 0.85, green: 0.65, blue: 0.85),  // Lavender
            "funk": Color(red: 1.0, green: 0.65, blue: 0.0),     // Orange
            "disco": Color(red: 1.0, green: 0.84, blue: 0.0),    // Gold
            "gospel": Color(red: 0.5, green: 0.5, blue: 1.0),    // Light blue
            "rap": Color.secondaryRed,                    // Cherry Chaos secondary
            "other": Color.secondary                      // System secondary
        ]
        if let c = palette[genre.lowercased()] { return c }
        
        // For unknown genres, generate distinct colors using a hash-based approach
        let lower = genre.lowercased()
        var hasher = Hasher()
        hasher.combine(lower)
        let hash = abs(hasher.finalize())
        
        // Generate distinct colors using HSV space
        let hue = Double(hash % 360) / 360.0
        let saturation = 0.7 + Double((hash / 360) % 3) * 0.1  // 0.7 to 0.9
        let brightness = 0.6 + Double((hash / 1080) % 4) * 0.1 // 0.6 to 0.9
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    // MARK: - Networking (track.getInfo to read duration + toptags)
    private static func fetchTrackMeta(artist: String, track: String, tagLimit: Int) async -> (durationSec: Double, tags: [String])? {
        guard !artist.isEmpty, !track.isEmpty else { return nil }

        var comps = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")
        comps?.queryItems = [
            .init(name: "method", value: "track.getInfo"),
            .init(name: "api_key", value: Secrets.apiKey),
            .init(name: "artist", value: artist),
            .init(name: "track", value: track),
            .init(name: "autocorrect", value: "1"),
            .init(name: "format", value: "json")
        ]
        guard let url = comps?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else { return nil }

            struct TrackInfoResponse: Decodable {
                struct Tag: Decodable { let name: String }
                // Last.fm sometimes returns either a single object or an array for `tag`
                enum OneOrMany<T: Decodable>: Decodable {
                    case one(T)
                    case many([T])
                    var asArray: [T] { switch self { case .one(let t): return [t]; case .many(let arr): return arr } }
                    init(from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        if let single = try? container.decode(T.self) {
                            self = .one(single)
                        } else {
                            self = .many(try container.decode([T].self))
                        }
                    }
                }
                struct TopTags: Decodable { let tag: OneOrMany<Tag>? }
                struct Inner: Decodable { let duration: String?; let toptags: TopTags? }
                let track: Inner
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let payload = try? decoder.decode(TrackInfoResponse.self, from: data) {
                let raw = Double(payload.track.duration ?? "0") ?? 0
                // Some responses return seconds; handle both by assuming ms if > 10_000
                var durationSec = raw > 10000 ? raw / 1000.0 : raw
                // Fallback when duration is unavailable
                if durationSec <= 0 { durationSec = 180 }

                let rawTags = payload.track.toptags?.tag?.asArray ?? []
                var names = rawTags.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if names.isEmpty {
                    names = await fetchArtistTopTags(artist: artist, limit: tagLimit)
                }
                if tagLimit > 0 { names = Array(names.prefix(tagLimit)) }
                return (durationSec: durationSec, tags: names)
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func fetchArtistTopTags(artist: String, limit: Int) async -> [String] {
        var comps = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")
        comps?.queryItems = [
            .init(name: "method", value: "artist.getTopTags"),
            .init(name: "api_key", value: Secrets.apiKey),
            .init(name: "artist", value: artist),
            .init(name: "autocorrect", value: "1"),
            .init(name: "format", value: "json")
        ]
        guard let url = comps?.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200 else { return [] }
            struct ArtistTopTagsResponse: Decodable {
                struct Tag: Decodable { let name: String; let count: Int? }
                struct Container: Decodable { let tag: [Tag]? }
                let toptags: Container?
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let payload = try? decoder.decode(ArtistTopTagsResponse.self, from: data) {
                let tags = payload.toptags?.tag ?? []
                let sorted = tags.sorted { ($0.count ?? 0) > ($1.count ?? 0) }
                let names = sorted.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if limit > 0 { return Array(names.prefix(limit)) }
                return names
            }
        } catch {
            return []
        }
        return []
    }

    // MARK: - Bucketing helpers
    private static func makeBucketStarts(in window: DateInterval, component: Calendar.Component, step: Int, calendar: Calendar) -> [Date] {
        var starts: [Date] = []
        // Align to the natural boundary of the component to avoid drifting (e.g., whole hour/day)
        var current = calendar.dateInterval(of: component, for: window.start)?.start ?? window.start
        // March forward in aligned steps, only collecting buckets within the window
        while current < window.end {
            if current >= window.start { starts.append(current) }
            guard let next = calendar.date(byAdding: component, value: step, to: current) else { break }
            current = next
        }
        return starts
    }
}


