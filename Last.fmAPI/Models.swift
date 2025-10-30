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
}

struct Artist: Decodable {
    let name: String
}
