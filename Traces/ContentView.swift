import SwiftUI
import Photos
import UIKit
import Combine

struct ContentView: View {
    @StateObject private var viewModel: PhotoLibraryViewModel
    @State private var navigationPath: [String] = []

    private let columnCount = 4
    private let gridSpacing: CGFloat = 2
    
    init(indexManager: IndexManager) {
        _viewModel = StateObject(
            wrappedValue: PhotoLibraryViewModel(indexManager: indexManager)
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.authorizationStatus {
                case .authorized, .limited:
                    photoGrid

                case .denied, .restricted:
                    ContentUnavailableView(
                        "Photo Access Disabled",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Enable photo access in Settings to let Traces show your library.")
                    )

                case .notDetermined:
                    VStack(spacing: 16) {
                        Image(systemName: "photo.stack")
                            .font(.largeTitle)

                        Text("Show Your Photo Library")
                            .font(.headline)

                        Button("Allow Photo Access") {
                            viewModel.requestAccessAndLoad()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                @unknown default:
                    Text("Unknown photo access state")
                }
            }
            .navigationTitle("Traces")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.loadIfAlreadyAuthorised()
            }
            .navigationDestination(for: String.self) { assetID in
                if let asset = viewModel.asset(withLocalIdentifier: assetID) {
                    PhotoDetailView(
                        asset: asset,
                        indexManager: viewModel.indexManager,
                        dismissToLibrary: {
                            navigationPath.removeAll()
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Photo Unavailable",
                        systemImage: "photo",
                        description: Text("This photo is no longer available.")
                    )
                }
            }
        }
    }

    private var photoGrid: some View {
        GeometryReader { proxy in
            let cellSize = (
                proxy.size.width - CGFloat(columnCount - 1) * gridSpacing
            ) / CGFloat(columnCount)

            let columns = Array(
                repeating: GridItem(.fixed(cellSize), spacing: gridSpacing),
                count: columnCount
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(viewModel.assets, id: \.localIdentifier) { asset in
                        NavigationLink(value: asset.localIdentifier) {
                            PhotoThumbnailView(asset: asset)
                                .frame(width: cellSize, height: cellSize)
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.topLeading, for: .alignment)
            .background(Color(.systemBackground))
        }
    }

}

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var assets: [PHAsset] = []
    
    let indexManager: IndexManager
    
    init(indexManager: IndexManager) {
        self.indexManager = indexManager
    }

    func loadIfAlreadyAuthorised() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return
        }

        loadAssets()
    }

    func requestAccessAndLoad() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard let self else {
                return
            }
            
            Task { @MainActor in
                self.authorizationStatus = status

                if status == .authorized || status == .limited {
                    self.loadAssets()
                }
            }
        }
    }

    func asset(withLocalIdentifier id: String) -> PHAsset? {
        if let asset = assets.first(where: { $0.localIdentifier == id }) {
            return asset
        }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    private func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        // TODO: Remove this and optimise properly.
        options.fetchLimit = 500

        let result = PHAsset.fetchAssets(with: .image, options: options)

        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }

        assets = fetchedAssets.reversed()
        let inputs = fetchedAssets.map(PhotoIndexInput.init(asset:))
        
        Task {
            do {
                let result = try await indexManager.indexPhotos(inputs)
                let total = try await indexManager.indexedPhotoCount()

                print(
                    "Indexed \(result.indexedCount) photos. " +
                    "Pruned \(result.prunedCount). " +
                    "Total indexed rows: \(total)"
                )
            } catch {
                print("Failed to index photos: \(error)")
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let asset: PHAsset

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

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
            if let requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    private func requestThumbnail() {
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 180 * scale, height: 180 * scale)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        requestID = PHImageManager.default().requestImage(
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
}

struct PhotoDetailView: View {
    private enum Section: Hashable {
        case photo
    }

    let asset: PHAsset
    let indexManager: IndexManager
    let dismissToLibrary: () -> Void

    private let bottomToolbarHeight: CGFloat = 82

    @State private var isShowingRelated = false
    @State private var image: UIImage?
    @State private var relatedAssets: [PHAsset] = []

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
                                relatedDetailsContent
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
            relatedAssets = []
            requestFullImage()
            await loadRelatedPhotos()
        }
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

    private var revealAnimation: Animation {
        .snappy(duration: 0.34, extraBounce: 0.04)
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

    private var relatedDetailsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if relatedAssets.isEmpty {
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
                ForEach(relatedAssets.prefix(3), id: \.localIdentifier) { asset in
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
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
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
    
    @MainActor
    private func loadRelatedPhotos() async {
        let input = PhotoIndexInput(asset: asset)

        do {
            let candidates = try await indexManager.relatedPhotos(
                for: input,
                limit: 3
            )
            let ids = candidates.map(\.id)
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: ids,
                options: nil
            )

            var fetchedAssetsByID: [String: PHAsset] = [:]
            fetchedAssetsByID.reserveCapacity(result.count)

            result.enumerateObjects { asset, _, _ in
                fetchedAssetsByID[asset.localIdentifier] = asset
            }

            relatedAssets = ids.compactMap { fetchedAssetsByID[$0] }
        } catch {
            print("Failed to load related photos: \(error)")
            relatedAssets = []
        }
    }
}

#Preview {
    let database = try! AppDatabase()
    ContentView(indexManager: IndexManager(store: database.indexStore))
}
