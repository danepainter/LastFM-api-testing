import SwiftUI

struct TrackRow: View {
    let index: Int
    let track: Track
    private let api = APIClient()
    @State private var resolvedURL: URL?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(index))
                .font(.headline)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            if let url = resolvedURL ?? track.imageURL {
                RemoteImage(url: url, width: 48, height: 48, cornerRadius: 6)
            } else {
                Color.gray.opacity(0.1)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.name).font(.headline)
                HStack(spacing: 8) {
                    if let artist = track.artist?.name {
                        Text(artist).foregroundStyle(.secondary)
                    }
                    if let pc = track.playcount {
                        Text("• \(pc) plays").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .task {
            // Always try to replace missing or placeholder art with album art
            let needsAlbumArt = track.imageURL == nil || (track.imageURL?.isLastFMPlaceholderImage ?? false)
            if resolvedURL == nil, needsAlbumArt, let artist = track.artist?.name {
                if let url = try? await api.fetchTrackImageURL(artist: artist, track: track.name) {
                    resolvedURL = url
                }
            }
        }
    }
}


