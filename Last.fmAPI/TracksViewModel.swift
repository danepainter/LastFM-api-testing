import SwiftUI
import Combine
@MainActor
final class TracksViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient()

    func load(user: String? = nil, period: String? = nil, limit: Int = 20) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let user, !user.isEmpty {
                tracks = try await api.fetchUserTopTracks(user: user, limit: limit, period: period)
            } else {
                tracks = try await api.fetchTopTracks(limit: limit)
            }
            if !tracks.isEmpty {
                let sample = tracks.prefix(5)
                for (idx, t) in sample.enumerated() {
                    let imgs = t.image?.map { "\($0.size ?? "?")=\($0.url)" }.joined(separator: ", ") ?? "nil"
                    print("[TopTracks] #\(idx+1) \(t.name) by \(t.artist?.name ?? "-") images: \(imgs)")
                }
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
}
