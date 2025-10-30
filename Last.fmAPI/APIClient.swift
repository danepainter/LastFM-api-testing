import Foundation

enum APIError: Error {
    case badURL
    case badResponse
}

struct APIClient {
    private let base = "https://ws.audioscrobbler.com/2.0/"
    private let apiKey = "MYAPIKEY" // replace this with your actual key

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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.badResponse }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(TopTracksResponse.self, from: data)
        return payload.tracks.track
    }
}