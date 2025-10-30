import Foundation

enum APIError: LocalizedError {
    case badURL
    case badResponse(status: Int, body: String?)
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid URL"
        case let .badResponse(status, body):
            return "HTTP " + String(status) + (body.flatMap { ": " + $0 } ?? "")
        case let .apiError(code, message):
            return "Last.fm (" + String(code) + "): " + message
        }
    }
}

private struct LastFMErrorResponse: Decodable {
    let error: Int
    let message: String
}

struct APIClient {
    private let base = "https://ws.audioscrobbler.com/2.0/"
    private let apiKey = Secrets.apiKey

    func fetchTopTracks(limit: Int = 20) async throws -> [Track] {
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            .init(name: "method", value: "chart.gettoptracks"),
            .init(name: "api_key", value: apiKey),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: String(limit))
        ]
        guard let url = comps?.url else { throw APIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 {
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                throw APIError.apiError(code: err.error, message: err.message)
            } else {
                let body = String(data: data, encoding: .utf8)
                throw APIError.badResponse(status: status, body: body)
            }
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(TopTracksResponse.self, from: data)
        return payload.tracks.track
    }

    func fetchUserTopTracks(user: String, limit: Int = 20, period: String? = nil) async throws -> [Track] {
        var comps = URLComponents(string: base)
        var items: [URLQueryItem] = [
            .init(name: "method", value: "user.gettoptracks"),
            .init(name: "api_key", value: apiKey),
            .init(name: "user", value: user),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: String(limit))
        ]
        if let period { items.append(.init(name: "period", value: period)) }
        comps?.queryItems = items
        guard let url = comps?.url else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 {
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                throw APIError.apiError(code: err.error, message: err.message)
            } else {
                let body = String(data: data, encoding: .utf8)
                throw APIError.badResponse(status: status, body: body)
            }
        }

        // user.getTopTracks returns { toptracks: { track: [...] } }
        struct UserTopTracksResponse: Decodable { struct Container: Decodable { let track: [Track] }; let toptracks: Container }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(UserTopTracksResponse.self, from: data)
        return payload.toptracks.track
    }

    // Fallback: fetch track.getInfo to obtain album images when list images are empty
    func fetchTrackImageURL(artist: String, track: String) async throws -> URL? {
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            .init(name: "method", value: "track.getInfo"),
            .init(name: "api_key", value: apiKey),
            .init(name: "artist", value: artist),
            .init(name: "track", value: track),
            .init(name: "format", value: "json")
        ]
        guard let url = comps?.url else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 {
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                throw APIError.apiError(code: err.error, message: err.message)
            } else {
                return nil
            }
        }

        struct TrackInfoResponse: Decodable {
            struct Album: Decodable { let image: [LastFMImage]? }
            struct Inner: Decodable { let album: Album? }
            let track: Inner
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let info = try? decoder.decode(TrackInfoResponse.self, from: data),
           let images = info.track.album?.image {
            let preferredOrder = ["mega", "extralarge", "large", "medium", "small"]
            for label in preferredOrder {
                if let found = images.first(where: { $0.size == label && !$0.url.isEmpty }), let u = found.url.asHTTPSUrl() {
                    return u
                }
            }
            if let any = images.last(where: { !$0.url.isEmpty }), let u = any.url.asHTTPSUrl() { return u }
        }
        return nil
    }

    // user.getRecentTracks supports from/to (unix timestamps). We'll fetch up to `limit` items.
    func fetchUserRecentTracks(user: String, from: Date, to: Date, limit: Int = 200) async throws -> [RecentTrack] {
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            .init(name: "method", value: "user.getRecentTracks"),
            .init(name: "api_key", value: apiKey),
            .init(name: "user", value: user),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: String(limit)),
            .init(name: "from", value: String(Int(from.timeIntervalSince1970))),
            .init(name: "to", value: String(Int(to.timeIntervalSince1970)))
        ]
        guard let url = comps?.url else { throw APIError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 {
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                throw APIError.apiError(code: err.error, message: err.message)
            } else {
                let body = String(data: data, encoding: .utf8)
                throw APIError.badResponse(status: status, body: body)
            }
        }

        struct RecentTracksResponse: Decodable {
            struct Container: Decodable { let track: [RecentTrack]? }
            let recenttracks: Container
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(RecentTracksResponse.self, from: data)
        return payload.recenttracks.track ?? []
    }

    // Helper to fetch a single page
    private func fetchUserRecentTracksPage(
        user: String,
        from: Date,
        to: Date,
        page: Int,
        pageSize: Int
    ) async throws -> (tracks: [RecentTrack], totalPages: Int) {
        struct RecentTracksResponse: Decodable {
            struct Attr: Decodable { let page: String; let totalPages: String }
            struct Container: Decodable { let track: [RecentTrack]?; let attr: Attr?
                enum CodingKeys: String, CodingKey { case track; case attr = "@attr" }
            }
            let recenttracks: Container
        }
        
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            .init(name: "method", value: "user.getRecentTracks"),
            .init(name: "api_key", value: apiKey),
            .init(name: "user", value: user),
            .init(name: "format", value: "json"),
            .init(name: "limit", value: String(pageSize)),
            .init(name: "page", value: String(page)),
            .init(name: "from", value: String(Int(from.timeIntervalSince1970))),
            .init(name: "to", value: String(Int(to.timeIntervalSince1970)))
        ]
        guard let url = comps?.url else { throw APIError.badURL }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 {
            if let err = try? JSONDecoder().decode(LastFMErrorResponse.self, from: data) {
                throw APIError.apiError(code: err.error, message: err.message)
            } else {
                let body = String(data: data, encoding: .utf8)
                throw APIError.badResponse(status: status, body: body)
            }
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(RecentTracksResponse.self, from: data)
        let pageTracks = payload.recenttracks.track ?? []
        let totalPages = Int(payload.recenttracks.attr?.totalPages ?? "1") ?? 1
        
        return (pageTracks, totalPages)
    }
    
    // Paginated fetch with parallel loading for faster performance
    func fetchUserRecentTracksAll(
        user: String,
        from: Date,
        to: Date,
        pageSize: Int = 200,
        maxPages: Int = 10,
        maxConcurrentRequests: Int = 10
    ) async throws -> [RecentTrack] {
        // First, fetch page 1 to get total page count
        let (firstPageTracks, totalPages) = try await fetchUserRecentTracksPage(
            user: user,
            from: from,
            to: to,
            page: 1,
            pageSize: pageSize
        )
        
        let pagesToFetch = min(totalPages, maxPages)
        guard pagesToFetch > 1 else {
            return firstPageTracks
        }
        
        // Fetch remaining pages in parallel (with concurrency limit)
        var results: [[RecentTrack]] = [firstPageTracks]
        var currentPage = 2
        
        while currentPage <= pagesToFetch {
            let batchEnd = min(currentPage + maxConcurrentRequests - 1, pagesToFetch)
            let batch = Array(currentPage...batchEnd)
            
            let batchResults = try await withThrowingTaskGroup(of: (page: Int, tracks: [RecentTrack]).self) { group in
                var batchTracks: [(page: Int, tracks: [RecentTrack])] = []
                
                for page in batch {
                    group.addTask {
                        let result = try await self.fetchUserRecentTracksPage(
                            user: user,
                            from: from,
                            to: to,
                            page: page,
                            pageSize: pageSize
                        )
                        return (page: page, tracks: result.tracks)
                    }
                }
                
                for try await result in group {
                    batchTracks.append(result)
                }
                
                // Sort by page number to maintain order
                return batchTracks.sorted { $0.page < $1.page }.map { $0.tracks }
            }
            
            results.append(contentsOf: batchResults)
            currentPage = batchEnd + 1
        }
        
        // Flatten all results
        return results.flatMap { $0 }
    }
}
