import SwiftUI
import Photos

struct RelatedPhotosSection: View {
    let assets: [PHAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if assets.isEmpty {
                emptyRelatedPhotos
            } else {
                relatedPhotosRow
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyRelatedPhotos: some View {
        Text("No related photos")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private var relatedPhotosRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related photos")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                ForEach(assets.prefix(3), id: \.localIdentifier) { asset in
                    NavigationLink(value: asset.localIdentifier) {
                        PhotoThumbnailView(asset: asset)
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
