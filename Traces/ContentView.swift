import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var viewModel: PhotoLibraryViewModel
    @State private var navigationPath: [String] = []
    
    init(
        indexManager: IndexManager,
        photoLibraryService: PhotoLibraryService = PhotoLibraryService()
    ) {
        _viewModel = StateObject(
            wrappedValue: PhotoLibraryViewModel(
                indexManager: indexManager,
                photoLibraryService: photoLibraryService
            )
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.authorizationStatus {
                case .authorized, .limited:
                    PhotoGridView(viewModel: viewModel)

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
}

#Preview {
    let database = try! AppDatabase()
    ContentView(indexManager: IndexManager(store: database.indexStore))
}
