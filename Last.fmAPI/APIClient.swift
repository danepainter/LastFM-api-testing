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
}
