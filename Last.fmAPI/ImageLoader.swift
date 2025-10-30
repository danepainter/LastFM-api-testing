import Foundation
import SwiftUI
import Combine

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024
    }
    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func insert(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL, cost: image.pngData()?.count ?? 0) }
}

final class ImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private var task: Task<Void, Never>?

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = .shared
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    func load(from url: URL?) {
        task?.cancel()
        error = nil
        guard let url else { image = nil; return }

        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        isLoading = true
        task = Task { [weak self] in
            defer { Task { @MainActor in self?.isLoading = false } }
            do {
                let (data, resp) = try await Self.session.data(from: url)
                guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw URLError(.badServerResponse)
                }
                if let img = UIImage(data: data) {
                    ImageCache.shared.insert(img, for: url)
                    await MainActor.run { self?.image = img }
                } else {
                    throw URLError(.cannotDecodeContentData)
                }
            } catch {
                await MainActor.run { self?.error = error; self?.image = nil }
            }
        }
    }

    deinit { task?.cancel() }
}

struct RemoteImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            if let uiImage = loader.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loader.isLoading {
                Color.gray.opacity(0.1)
            } else {
                Color.gray.opacity(0.2)
                    .overlay(
                        Group { if let error = loader.error { Text("") .onAppear { print("RemoteImage failed for URL: \(url?.absoluteString ?? "nil") —", error.localizedDescription) } } }
                    )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear { loader.load(from: url) }
        .onChange(of: url) { _, newValue in loader.load(from: newValue) }
    }
}


