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
}