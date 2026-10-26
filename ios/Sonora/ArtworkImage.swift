import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shared artwork renderer supports sandbox covers as well as public remote renditions.
struct ArtworkImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    @State private var localImage: UIImage?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if url?.isFileURL == true {
                if let localImage { content(Image(uiImage: localImage)) }
                else { placeholder() }
            } else { AsyncImage(url: url, content: content, placeholder: placeholder) }
        }
        .task(id: url) {
            localImage = nil
            guard let url, url.isFileURL, let data = try? await ArtworkFiles.shared.data(url), !Task.isCancelled else { return }
            localImage = UIImage(data: data)
        }
    }
}

/// Encoded cover data crosses actors; file reads and thumbnail generation stay off the UI thread.
actor ArtworkFiles {
    static let shared = ArtworkFiles()
    private let cache = NSCache<NSURL, NSData>()
    private static let maximumData = 20 * 1_024 * 1_024
    private static let maximumPixels = 1_600
    static var root: URL { URL.applicationSupportDirectory.appendingPathComponent("Audio/Artwork", isDirectory: true) }

    init() { cache.totalCostLimit = Self.maximumData }

    func data(_ url: URL) async throws -> Data {
        if let cached = cache.object(forKey: url as NSURL) { return cached as Data }
        let data: Data
        if url.isFileURL {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0, size <= Self.maximumData else { throw CocoaError(.fileReadTooLarge) }
            data = try Data(contentsOf: url)
        } else {
            let (received, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, received.count <= Self.maximumData else { throw URLError(.badServerResponse) }
            data = received
        }
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    /// Normalizes orientation and bounds decoded cover size before making a durable local rendition.
    func save(_ data: Data, id: UUID) throws -> String {
        guard data.count <= Self.maximumData, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixels,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        let filename = id.uuidString + ".jpg"
        try (output as Data).write(to: Self.root.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func remove(_ filename: String) {
        guard URL(fileURLWithPath: filename).lastPathComponent == filename else { return }
        let url = Self.root.appendingPathComponent(filename)
        cache.removeObject(forKey: url as NSURL)
        try? FileManager.default.removeItem(at: url)
    }
}
