import SwiftUI
import Photos
import UIKit
import Combine

// MARK: - Grid Size Enum
enum GridSize: String, CaseIterable, Identifiable {
    case threeByThree = "3x3"
    case fiveByFive = "5x5"
    case sevenBySeven = "7x7"
    case tenByTen = "10x10"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var dimension: Int {
        switch self {
        case .threeByThree: return 3
        case .fiveByFive: return 5
        case .sevenBySeven: return 7
        case .tenByTen: return 10
        }
    }
    
    var totalImages: Int {
        dimension * dimension
    }
}

// MARK: - Export Date Range Enum
enum ExportDateRange: String, CaseIterable, Identifiable {
    case sevenDays = "7d"
    case oneMonth = "1mo"
    case threeMonths = "3mo"
    case sixMonths = "6mo"
    case oneYear = "1yr"
    case allTime = "All time"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var apiValue: String? {
        switch self {
        case .sevenDays: return "7day"
        case .oneMonth: return "1month"
        case .threeMonths: return "3month"
        case .sixMonths: return "6month"
        case .oneYear: return "12month"
        case .allTime: return "overall"
        }
    }
    
    var displayTitle: String {
        switch self {
        case .sevenDays: return "7 days"
        case .oneMonth: return "1 month"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        case .allTime: return "All Time"
        }
    }
}

// MARK: - Grid Image Generator View Model
@MainActor
class GridImageGenerator: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isGeneratingImage = false
    @Published var generationProgress: Double = 0.0
    
    private let api = APIClient()
    private var imageLoaders: [String: ImageLoader] = [:]
    
    func loadTracks(user: String?, dateRange: ExportDateRange, limit: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            if let user, !user.isEmpty {
                tracks = try await api.fetchUserTopTracks(user: user, limit: limit, period: dateRange.apiValue)
            } else {
                tracks = try await api.fetchTopTracks(limit: limit)
            }
            
            // Preload images for the tracks
            await preloadImages()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
    
    private func preloadImages() async {
        let tracksNeedingImages = tracks.prefix(min(tracks.count, 100))
        
        await withTaskGroup(of: Void.self) { group in
            for track in tracksNeedingImages {
                group.addTask { [weak self] in
                    await self?.loadImageForTrack(track)
                }
            }
        }
    }
    
    private func loadImageForTrack(_ track: Track) async {
        // Check if we have a valid image URL
        if let url = track.imageURL, !url.isLastFMPlaceholderImage {
            if imageLoaders[track.id] == nil {
                let loader = ImageLoader()
                imageLoaders[track.id] = loader
                loader.load(from: url)
                // Wait a bit for image to load
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            return
        }
        
        // Try to fetch album art if missing
        if let artist = track.artist?.name {
            if let url = try? await api.fetchTrackImageURL(artist: artist, track: track.name) {
                if imageLoaders[track.id] == nil {
                    let loader = ImageLoader()
                    imageLoaders[track.id] = loader
                    loader.load(from: url)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }
    
    func getImageForTrack(_ track: Track) -> UIImage? {
        if let loader = imageLoaders[track.id], let image = loader.image {
            return image
        }
        return nil
    }
    
    func generateGridImage(size: GridSize, dateRange: ExportDateRange, username: String?) async -> UIImage? {
        // Note: isGeneratingImage is managed by the caller to allow it to stay true during save
        generationProgress = 0.0
        
        let neededCount = size.totalImages
        let availableTracks = Array(tracks.prefix(neededCount))
        
        // Ensure we have enough tracks
        if availableTracks.count < neededCount {
            return nil
        }
        
        // Ensure all images are loaded
        for (index, track) in availableTracks.enumerated() {
            await loadImageForTrack(track)
            // Update progress on main thread
            await MainActor.run {
                generationProgress = Double(index + 1) / Double(neededCount)
            }
        }
        
        // Update progress to indicate we're rendering
        await MainActor.run {
            generationProgress = 0.95 // 95% - rendering the grid
        }
        
        // Generate the grid image
        let dimension = size.dimension
        let imageSize: CGFloat = 1024 // Base size for high quality
        let cellSize = imageSize / CGFloat(dimension)
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageSize, height: imageSize))
        let image = renderer.image { context in
            // Fill with black background
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: imageSize, height: imageSize)))
            
            for (index, track) in availableTracks.enumerated() {
                let row = index / dimension
                let col = index % dimension
                let x = CGFloat(col) * cellSize
                let y = CGFloat(row) * cellSize
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                
                if let uiImage = getImageForTrack(track) {
                    // Draw image to fill the cell completely (aspect fill - may crop)
                    // Save graphics state to clip to cell bounds
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: rect)
                    
                    // Calculate rect to fill while maintaining aspect ratio
                    let imageAspect = uiImage.size.width / uiImage.size.height
                    let cellAspect = rect.width / rect.height
                    
                    var drawRect = rect
                    if imageAspect > cellAspect {
                        // Image is wider - fill width, center vertically
                        let scaledHeight = rect.width / imageAspect
                        drawRect = CGRect(
                            x: rect.origin.x,
                            y: rect.midY - scaledHeight / 2,
                            width: rect.width,
                            height: scaledHeight
                        )
                    } else {
                        // Image is taller - fill height, center horizontally
                        let scaledWidth = rect.height * imageAspect
                        drawRect = CGRect(
                            x: rect.midX - scaledWidth / 2,
                            y: rect.origin.y,
                            width: scaledWidth,
                            height: rect.height
                        )
                    }
                    
                    uiImage.draw(in: drawRect)
                    context.cgContext.restoreGState()
                } else {
                    // Draw placeholder with gray background
                    UIColor.darkGray.setFill()
                    context.fill(rect)
                    
                    // Draw music note icon in center
                    let iconSize = cellSize * 0.3
                    let iconRect = CGRect(
                        x: x + (cellSize - iconSize) / 2,
                        y: y + (cellSize - iconSize) / 2,
                        width: iconSize,
                        height: iconSize
                    )
                    
                    if let systemImage = UIImage(systemName: "music.note") {
                        let config = UIImage.SymbolConfiguration(pointSize: iconSize * 0.6)
                        let placeholderImage = systemImage.withConfiguration(config)
                        let tintedImage = placeholderImage.withTintColor(.lightGray)
                        tintedImage.draw(in: iconRect, blendMode: .normal, alpha: 0.6)
                    }
                }
            }
        }
        
        return image
    }
    
    func saveToPhotoLibrary(_ image: UIImage) async throws {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "GridImageGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save image"]))
                }
            })
        }
    }
}

// MARK: - UIImage Extension for Symbol Configuration
extension UIImage {
    func withTintColor(_ color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size), blendMode: .destinationIn, alpha: 1.0)
        }
    }
}

