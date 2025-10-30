import Foundation
import Combine
import SwiftUI

@MainActor
final class DailyActivityChartViewModel: ObservableObject {
    struct DailyPoint: Identifiable {
        let id = UUID()
        let date: Date
        let playCount: Int
    }
    
    @Published var points: [DailyPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let api = APIClient()
    
    func load(user: String, in window: DateInterval) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let recent = try await api.fetchUserRecentTracksAll(
                user: user,
                from: window.start,
                to: window.end,
                pageSize: 200,
                maxPages: 10
            )
            
            let dailyData = aggregateByDay(recent)
            self.points = dailyData.sorted { $0.date < $1.date }
        } catch {
            self.errorMessage = error.localizedDescription
            self.points = []
        }
    }
    
    private func aggregateByDay(_ tracks: [RecentTrack]) -> [DailyPoint] {
        let calendar = Calendar.current
        var dayCounts: [Date: Int] = [:]
        
        for track in tracks {
            guard let uts = Double(track.uts) else { continue }
            let date = Date(timeIntervalSince1970: uts)
            let day = calendar.startOfDay(for: date)
            dayCounts[day, default: 0] += 1
        }
        
        return dayCounts.map { DailyPoint(date: $0.key, playCount: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

