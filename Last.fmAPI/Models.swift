import Foundation

struct TopTracksResponse: Decodable {
    let tracks: Tracks
}

struct Tracks: Decodable {
    let track: [Track]
}

struct Track: Identifiable, Decodable {
    var id: String { mbid?.isEmpty == false ? mbid! : name + (artist?.name ?? "") }
    let name: String
    let mbid: String?
    let artist: Artist?
    let url: String?
    let playcount: String?
    let image: [LastFMImage]?
}

struct Artist: Decodable {
    let name: String
}

struct LastFMImage: Decodable {
    let url: String
    let size: String?
    enum CodingKeys: String, CodingKey { case url = "#text"; case size }
}

extension Track {
    var imageURL: URL? {
        // Prefer larger images if available; fall back to any non-empty URL
        let preferredOrder = ["mega", "extralarge", "large", "medium", "small"]
        if let image {
            for label in preferredOrder {
                if let found = image.first(where: { $0.size == label && !$0.url.isEmpty }), let u = found.url.asHTTPSUrl() {
                    return u
                }
            }
            if let any = image.last(where: { !$0.url.isEmpty }), let u = any.url.asHTTPSUrl() { return u }
        }
        return nil
    }
}

extension String {
    func asHTTPSUrl() -> URL? {
        if self.hasPrefix("http://") {
            var comps = URLComponents(string: self)
            comps?.scheme = "https"
            return comps?.url
        }
        return URL(string: self)
    }
}

extension URL {
    // Last.fm returns a known placeholder hash when artwork is unavailable
    var isLastFMPlaceholderImage: Bool {
        absoluteString.contains("2a96cbd8b46e442fc41c2b86b821562f.png")
    }
}
