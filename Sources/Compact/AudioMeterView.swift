import SwiftUI

/// 12-segment horizontal level bar: green, then yellow, then red.
struct AudioMeterView: View {
    let level: Double
    private let segments = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(i).opacity(Double(i) < level * Double(segments) ? 1 : 0.18))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func color(_ i: Int) -> Color {
        i < 7 ? .green : (i < 10 ? .yellow : .red)
    }
}
