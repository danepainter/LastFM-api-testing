import SwiftUI
import Combine
@MainActor
final class TracksViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient()

    func load(user: String? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let user, !user.isEmpty {
                tracks = try await api.fetchUserTopTracks(user: user)
            } else {
                tracks = try await api.fetchTopTracks()
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
}