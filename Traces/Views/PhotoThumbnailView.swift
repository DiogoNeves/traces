import SwiftUI
import Photos
import UIKit

struct PhotoThumbnailView: View {
    let asset: PHAsset

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    private static let imageManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.gray.opacity(0.25))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .onAppear {
            requestThumbnail()
        }
        .onDisappear {
            cancelThumbnailRequest()
        }
    }

    private func requestThumbnail() {
        let targetSize = CGSize(
            width: 180 * displayScale,
            height: 180 * displayScale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        Self.imageManager.startCachingImages(
            for: [asset],
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )

        requestID = Self.imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.image = image
            }
        }
    }

    private func cancelThumbnailRequest() {
        let targetSize = CGSize(
            width: 180 * displayScale,
            height: 180 * displayScale
        )

        if let requestID {
            Self.imageManager.cancelImageRequest(requestID)
        }

        Self.imageManager.stopCachingImages(
            for: [asset],
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}
