import SwiftUI
import Photos

struct PhotoGridView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    private let columnCount = 4
    private let gridSpacing: CGFloat = 2

    var body: some View {
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
                    ForEach(0..<viewModel.assetCount, id: \.self) { index in
                        PhotoGridCell(
                            asset: viewModel.asset(at: index),
                            cellSize: cellSize
                        )
                    }
                }
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.topLeading, for: .alignment)
            .background(Color(.systemBackground))
        }
    }
}

private struct PhotoGridCell: View {
    let asset: PHAsset?
    let cellSize: CGFloat

    var body: some View {
        Group {
            if let asset {
                NavigationLink(value: asset.localIdentifier) {
                    PhotoThumbnailView(asset: asset)
                        .frame(width: cellSize, height: cellSize)
                        .clipped()
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: cellSize, height: cellSize)
            }
        }
    }
}
