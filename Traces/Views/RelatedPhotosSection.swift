import SwiftUI
import Photos

struct RelatedPhotoAssetSection: Identifiable {
    let id: RelatedPhotoSectionKind
    let title: String
    let assets: [PHAsset]
}

struct RelatedPhotosSection: View {
    let sections: [RelatedPhotoAssetSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if sections.isEmpty {
                emptyRelatedPhotos
            } else {
                ForEach(sections) { section in
                    relatedPhotosRow(section)
                }
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

    private func relatedPhotosRow(
        _ section: RelatedPhotoAssetSection
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(section.assets, id: \.localIdentifier) { asset in
                        NavigationLink(value: asset.localIdentifier) {
                            PhotoThumbnailView(asset: asset)
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
