import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI
import UIKit

/// Accent options include the system colors and a contrast-adjusted color from the current artwork.
enum AppAccent: String, CaseIterable, Identifiable {
    case music, artwork, blue, purple, orange, green
    var id: String { rawValue }
    var labelKey: LocalizedStringKey {
        switch self {
        case .music: "ios-accent-music"
        case .artwork: "ios-accent-artwork"
        case .blue: "ios-accent-blue"
        case .purple: "ios-accent-purple"
        case .orange: "ios-accent-orange"
        case .green: "ios-accent-green"
        }
    }
}

/// Owns the artwork request so changing tracks cancels an obsolete theme calculation.
@MainActor @Observable
final class AppearanceStore {
    private(set) var artworkAccent: Color = .pink
    private var currentURL: URL?
    @ObservationIgnored private var task: Task<Void, Never>?

    func color(for accent: AppAccent) -> Color {
        switch accent {
        case .music: .pink
        case .artwork: artworkAccent
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .green: .green
        }
    }

    /// A small public thumbnail is enough for a hue; no full-size artwork is decoded here.
    func updateArtwork(_ original: URL?) {
        guard currentURL != original else { return }
        currentURL = original
        task?.cancel()
        artworkAccent = .pink
        guard let url = ArtworkRendition.url(original, side: Layout.rowArtwork),
              url.scheme == "https" || url.isFileURL else { return }
        task = Task { [weak self] in
            do {
                let data = try await ArtworkFiles.shared.data(url)
                guard !Task.isCancelled, let self, self.currentURL == original,
                      data.count <= 4 * 1_024 * 1_024,
                      let image = CIImage(data: data) else { return }
                let average = CIFilter.areaAverage()
                average.inputImage = image
                average.extent = image.extent
                guard let output = average.outputImage else { return }
                var rgba = [UInt8](repeating: 0, count: 4)
                CIContext(options: [.useSoftwareRenderer: true]).render(output, toBitmap: &rgba,
                    rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
                let sample = UIColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255,
                    blue: CGFloat(rgba[2]) / 255, alpha: 1)
                var hue: CGFloat = 0, saturation: CGFloat = 0
                guard sample.getHue(&hue, saturation: &saturation, brightness: nil, alpha: nil), saturation > 0.12 else { return }
                let chosenHue = hue
                let chosenSaturation = max(saturation, 0.65)
                self.artworkAccent = Color(uiColor: UIColor { traits in
                    UIColor(hue: chosenHue, saturation: chosenSaturation,
                        brightness: traits.userInterfaceStyle == .dark ? 0.95 : 0.55, alpha: 1)
                })
            } catch {
                // The system Music accent remains usable offline or when artwork fails.
            }
        }
    }
}
