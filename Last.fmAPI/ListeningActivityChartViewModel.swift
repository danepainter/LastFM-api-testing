import Foundation
import Combine
import SwiftUI

@MainActor
final class ListeningActivityChartViewModel: ObservableObject {
    struct DailyPoint: Identifiable {
        let id = UUID()
        let date: Date
        let playCount: Int
    }
    
    @Published var points: [DailyPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let api = APIClient()
    
    func load(user: String, in window: DateInterval, maxPages: Int = 50, aggregationUnit: Calendar.Component = .day) async {
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
                maxPages: maxPages
            )
            
            let aggregatedData = aggregate(recent, by: aggregationUnit)
            self.points = aggregatedData.sorted { $0.date < $1.date }
        } catch {
            self.errorMessage = error.localizedDescription
            self.points = []
        }
    }
    
    private func aggregateByDay(_ tracks: [RecentTrack]) -> [DailyPoint] {
        aggregate(tracks, by: .day)
    }
    
    private func aggregate(_ tracks: [RecentTrack], by component: Calendar.Component) -> [DailyPoint] {
        let calendar = Calendar.current
        var bucketCounts: [Date: Int] = [:]
        
        // Process tracks in a single pass - efficient counting
        for track in tracks {
            guard let uts = Double(track.uts) else { continue }
            let date = Date(timeIntervalSince1970: uts)
            
            // Group by the specified calendar component
            let bucket: Date
            switch component {
            case .day:
                bucket = calendar.startOfDay(for: date)
            case .weekOfYear:
                // Get the start of the week containing this date
                bucket = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
            case .month:
                bucket = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
            default:
                bucket = calendar.startOfDay(for: date)
            }
            
            bucketCounts[bucket, default: 0] += 1
        }
        
        // Convert to array and sort
        return bucketCounts.map { DailyPoint(date: $0.key, playCount: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

