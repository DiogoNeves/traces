import SwiftUI
import Photos
import UIKit
import Combine

struct ContentView: View {
    @StateObject private var viewModel: PhotoLibraryViewModel

    private let columnCount = 4
    private let gridSpacing: CGFloat = 2
    
    init(indexManager: IndexManager) {
        _viewModel = StateObject(
            wrappedValue: PhotoLibraryViewModel(indexManager: indexManager)
        )
    }

    var body: some View {
        NavigationStack {
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
                        NavigationLink {
                            PhotoDetailView(asset: asset)
                        } label: {
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
            .background(Color.black)
        }
    }
}

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var assets: [PHAsset] = []
    
    private let indexManager: IndexManager
    
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
                let indexedCount = try await indexManager.indexPhotos(inputs)
                let total = try await indexManager.indexedPhotoCount()
                print("Indexed \(indexedCount) photos. Total indexed rows: \(total)")
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
    let asset: PHAsset

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            requestFullImage()
        }
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
}

#Preview {
    let database = try! AppDatabase()
    ContentView(indexManager: IndexManager(store: database.indexStore))
}
