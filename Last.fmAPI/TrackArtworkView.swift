import SwiftUI

struct TrackArtworkView: View {
    let track: Track
    private let api = APIClient()
    @State private var resolvedURL: URL?
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            
            ZStack {
                if let url = resolvedURL ?? track.imageURL {
                    RemoteImage(url: url, width: size, height: size, cornerRadius: 8)
                } else {
                    Color.gray.opacity(0.2)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.gray.opacity(0.5))
                                .font(.system(size: size * 0.3))
                        )
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            // Try to replace missing or placeholder art with album art
            let needsAlbumArt = track.imageURL == nil || (track.imageURL?.isLastFMPlaceholderImage ?? false)
            if resolvedURL == nil, needsAlbumArt, let artist = track.artist?.name {
                if let url = try? await api.fetchTrackImageURL(artist: artist, track: track.name) {
                    resolvedURL = url
                }
            }
        }
    }
}

