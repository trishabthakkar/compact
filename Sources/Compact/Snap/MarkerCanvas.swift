import SwiftUI

struct MarkerStroke: Identifiable {
    let id: UUID
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
}

/// Draws strokes in the coordinate space of the view it overlays (the photo), clipped to its bounds.
struct MarkerCanvas: View {
    @Binding var strokes: [MarkerStroke]
    var color: Color
    var enabled: Bool

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                var path = Path()
                path.move(to: first)
                if stroke.points.count == 1 {
                    path.addLine(to: first) // a tap draws a dot via the round cap
                } else {
                    for p in stroke.points.dropFirst() { path.addLine(to: p) }
                }
                ctx.stroke(path, with: .color(stroke.color),
                           style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard enabled else { return }
                append(value)
            }
            .onEnded { _ in activeID = nil })
    }

    @State private var activeID: UUID?

    private func append(_ value: DragGesture.Value) {
        if let id = activeID, let i = strokes.firstIndex(where: { $0.id == id }) {
            strokes[i].points.append(value.location)
        } else {
            let s = MarkerStroke(id: UUID(), points: [value.startLocation], color: color, width: 4)
            activeID = s.id
            strokes.append(s)
        }
    }
}
