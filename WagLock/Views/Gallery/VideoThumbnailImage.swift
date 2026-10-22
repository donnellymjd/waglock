import SwiftUI

/// Letterboxes video previews without changing their intrinsic aspect ratio or orientation.
/// The surrounding grid/card supplies its tile size; only video pixels are fitted inside it.
struct VideoThumbnailImage: View {
    let image: UIImage

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}
