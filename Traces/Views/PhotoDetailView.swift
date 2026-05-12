import SwiftUI
import Photos
import UIKit

struct PhotoDetailView: View {
    private enum Section: Hashable {
        case photo
    }

    let asset: PHAsset
    let indexManager: IndexManager
    let dismissToLibrary: () -> Void

    private let bottomToolbarHeight: CGFloat = 82

    @Environment(\.displayScale) private var displayScale
    @State private var isShowingRelated = false
    @State private var image: UIImage?
    @State private var imageRequestID: PHImageRequestID?
    @State private var relatedSections: [RelatedPhotoAssetSection] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(.systemBackground).ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            photoContent
                                .frame(
                                    width: proxy.size.width,
                                    height: photoAreaHeight(for: proxy.size),
                                    alignment: .center
                                )
                                .clipped()
                                .contentShape(Rectangle())
                                .id(Section.photo)
                                .gesture(relatedRevealGesture(scrollProxy: scrollProxy))

                            if isShowingRelated {
                                RelatedPhotosSection(sections: relatedSections)
                                    .transition(.opacity)
                            }

                            Color.clear.frame(height: bottomToolbarHeight + 16)
                        }
                        .frame(
                            minHeight: proxy.size.height,
                            alignment: isShowingRelated ? .top : .center
                        )
                    }
                    .background(Color(.systemBackground))
                    .ignoresSafeArea(edges: isShowingRelated ? .top : [])
                    .animation(revealAnimation, value: isShowingRelated)

                    bottomToolbar(scrollProxy: scrollProxy)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                detailDatePill
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: dismissToLibrary) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Back to library")
            }
        }
        .task(id: asset.localIdentifier) {
            isShowingRelated = false
            image = nil
            relatedSections = []
            requestFullImage()
            await loadRelatedPhotos()
        }
        .onDisappear {
            cancelFullImageRequest()
        }
    }

    private var revealAnimation: Animation {
        .snappy(duration: 0.34, extraBounce: 0.04)
    }

    private var formattedDateText: String? {
        guard let creationDate = asset.creationDate else {
            return nil
        }

        return creationDate.formatted(
            .dateTime
                .day()
                .month(.wide)
                .year()
        )
    }

    private var formattedTimeText: String? {
        guard let creationDate = asset.creationDate else {
            return nil
        }

        return creationDate.formatted(
            .dateTime
                .hour()
                .minute()
        )
    }

    private func photoAreaHeight(for size: CGSize) -> CGFloat {
        guard isShowingRelated else {
            return max(size.height - bottomToolbarHeight, size.height * 0.72)
        }

        return size.width
    }

    private func relatedRevealGesture(scrollProxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if value.translation.height < -40 {
                    setRelatedPanelVisible(true, scrollProxy: scrollProxy)
                } else if value.translation.height > 40 {
                    setRelatedPanelVisible(false, scrollProxy: scrollProxy)
                }
            }
    }

    private func setRelatedPanelVisible(
        _ isVisible: Bool,
        scrollProxy: ScrollViewProxy
    ) {
        withAnimation(revealAnimation) {
            isShowingRelated = isVisible
        }

        if isVisible {
            DispatchQueue.main.async {
                withAnimation(revealAnimation) {
                    scrollProxy.scrollTo(Section.photo, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var detailDatePill: some View {
        if let formattedDateText, let formattedTimeText {
            VStack(spacing: 0) {
                Text(formattedDateText)
                    .font(.subheadline.weight(.semibold))

                Text(formattedTimeText)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .frame(minWidth: 146)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(formattedDateText), \(formattedTimeText)")
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(
                    contentMode: isShowingRelated ? .fill : .fit
                )
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private func bottomToolbar(scrollProxy: ScrollViewProxy) -> some View {
        HStack {
            Spacer()

            HStack(spacing: 18) {
                Button {
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 34, height: 44)
                }
                .accessibilityLabel("Share")

                Button {
                    setRelatedPanelVisible(
                        !isShowingRelated,
                        scrollProxy: scrollProxy
                    )
                } label: {
                    Image(
                        systemName: isShowingRelated
                            ? "info.circle.fill"
                            : "info.circle"
                    )
                    .frame(width: 34, height: 44)
                }
                .accessibilityLabel(
                    isShowingRelated
                        ? "Hide related photos"
                        : "Show related photos"
                )
            }
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(height: bottomToolbarHeight)
    }

    private func requestFullImage() {
        cancelFullImageRequest()

        let targetSize = CGSize(
            width: 900 * displayScale,
            height: 900 * displayScale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageRequestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.image = image
            }
        }
    }

    private func cancelFullImageRequest() {
        if let imageRequestID {
            PHImageManager.default().cancelImageRequest(imageRequestID)
            self.imageRequestID = nil
        }
    }

    @MainActor
    private func loadRelatedPhotos() async {
        let input = PhotoIndexInput(asset: asset)

        do {
            let sections = try await indexManager.relatedSections(
                for: input,
                limitPerSection: 6
            )
            let ids = sections.flatMap { section in
                section.candidates.map(\.id)
            }
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: ids,
                options: nil
            )

            var fetchedAssetsByID: [String: PHAsset] = [:]
            fetchedAssetsByID.reserveCapacity(result.count)

            result.enumerateObjects { asset, _, _ in
                fetchedAssetsByID[asset.localIdentifier] = asset
            }

            relatedSections = sections.compactMap { section in
                let assets = section.candidates.compactMap {
                    fetchedAssetsByID[$0.id]
                }

                guard !assets.isEmpty else {
                    return nil
                }

                return RelatedPhotoAssetSection(
                    id: section.kind,
                    title: section.title,
                    assets: assets
                )
            }
        } catch {
            print("Failed to load related photos: \(error)")
            relatedSections = []
        }
    }
}
