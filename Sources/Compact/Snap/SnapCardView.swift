import SwiftUI
import AppKit
import CompactCore

/// A snap with its chosen frame. With `.none` it's just the photo.
/// Laid out at `photoWidth`; when saving, render at `image.width / photoWidth` scale for full resolution.
struct SnapCardView: View {
    let image: CGImage
    let frame: SnapFrame
    let includeDate: Bool
    let date: Date

    static let photoWidth: CGFloat = 320

    var photoSize: CGSize {
        CGSize(width: Self.photoWidth, height: Self.photoWidth * CGFloat(image.height) / CGFloat(image.width))
    }

    var body: some View {
        switch frame {
        case .none:
            photo
        case .polaroid:
            VStack(spacing: 0) {
                photo.clipShape(RoundedRectangle(cornerRadius: 3))
                Text(includeDate ? date.formatted(date: .long, time: .omitted) : " ")
                    .font(.custom("Marker Felt", size: 18))
                    .foregroundStyle(Color(white: 0.2))
                    .frame(width: photoSize.width, height: 56)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(Color.white)
        case .white:
            photo.padding(14).background(Color.white)
        case .black:
            photo.padding(14).background(Color.black)
        case .film:
            VStack(spacing: 0) {
                sprockets
                photo
                sprockets
            }
            .padding(.horizontal, 10)
            .background(Color(white: 0.08))
        }
    }

    private var photo: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: photoSize.width, height: photoSize.height)
    }

    /// A row of rounded holes along a film strip edge.
    private var sprockets: some View {
        HStack(spacing: 9) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(white: 0.85))
                    .frame(width: 11, height: 8)
            }
        }
        .frame(width: photoSize.width, height: 22)
    }
}
