import SwiftUI
import AppKit

/// The polaroid card. The photo area is its own view so a drawing canvas can be overlaid on it only.
struct SnapCardView: View {
    let image: CGImage
    let includeDate: Bool
    let date: Date

    static let photoWidth: CGFloat = 320

    var photoSize: CGSize {
        CGSize(width: Self.photoWidth, height: Self.photoWidth * CGFloat(image.height) / CGFloat(image.width))
    }

    var body: some View {
        VStack(spacing: 0) {
            photo
            caption
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .background(Color.white)
    }

    /// Task 5 overlays its canvas here.
    var photo: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: photoSize.width, height: photoSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var caption: some View {
        Text(includeDate ? date.formatted(date: .long, time: .omitted) : " ")
            .font(.custom("Marker Felt", size: 18))
            .foregroundStyle(Color(white: 0.2))
            .frame(width: photoSize.width, height: 56)
    }
}
