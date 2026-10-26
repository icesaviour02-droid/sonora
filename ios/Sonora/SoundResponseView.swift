import Charts
import SwiftUI

struct SoundResponsePoint: Decodable, Identifiable {
    let frequency: Double
    let output_db: Double
    var id: Double { frequency }
}

/// Graphs the desktop DSP's actual response; previews never apply an unsaved sound profile.
struct SoundResponseView: View {
    let profile: SoundProfile
    @State private var points: [SoundResponsePoint] = []
    @State private var error = false
    @State private var loading = true

    private struct Input: Hashable {
        let filters: [SoundFilter]
        let automatic: Bool
        let preamp: Double
    }
    private var input: Input { Input(filters: profile.filters, automatic: profile.autoPreamp, preamp: profile.preampDB) }
    private var outputRange: ClosedRange<Double> {
        let low = max(-60, min(-24, floor((points.map(\.output_db).min() ?? 0) / 6) * 6))
        let high = min(48, max(12, ceil((points.map(\.output_db).max() ?? 0) / 6) * 6))
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.compact) {
            Text("ios-sound-response").appFont(.headline)
            Group {
                if error { Text("ios-sound-response-error").foregroundStyle(.secondary) }
                else if loading { ProgressView().frame(maxWidth: .infinity) }
                else { responseChart }
            }
            .frame(height: Layout.soundResponseHeight)
            Text("ios-sound-response-description").appFont(.caption).foregroundStyle(.secondary)
        }
        .task(id: input) {
            loading = true
            error = false
            do {
                let response = try await NativeProvider.describeEqualizer([
                    "operation": "equalizer_describe", "preset": "flat", "filters": input.filters.map(\.payload),
                    "auto_preamp": input.automatic, "preamp_db": input.preamp
                ])
                try Task.checkCancellation()
                points = response.response
                loading = false
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                self.error = true
            }
        }
    }

    private var responseChart: some View {
        Chart {
            RuleMark(y: .value(String(localized: "ios-response-db"), 0))
                .foregroundStyle(Color.secondary.opacity(0.3))
            ForEach(points) { point in
                LineMark(x: .value(String(localized: "ios-filter-frequency"), point.frequency),
                         y: .value(String(localized: "ios-response-db"), point.output_db))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: 20.0...20_000.0, type: .log)
        .chartYScale(domain: outputRange)
        .chartXAxis {
            AxisMarks(values: [20.0, 100.0, 1_000.0, 10_000.0, 20_000.0]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let frequency = value.as(Double.self) {
                        Text(frequency, format: .number.notation(.compactName)).appFont(.caption2)
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) }
        .accessibilityLabel(Text("ios-sound-response"))
    }
}
