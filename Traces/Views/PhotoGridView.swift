import SwiftUI
import Photos

struct PhotoGridView: View {
    private enum ScrollTarget: Hashable {
        case latest
    }

    @ObservedObject var viewModel: PhotoLibraryViewModel

    private let columnCount = 4
    private let gridSpacing: CGFloat = 2

    @State private var showsScrollToLatestButton = false

    var body: some View {
        GeometryReader { proxy in
            let cellSize = (
                proxy.size.width - CGFloat(columnCount - 1) * gridSpacing
            ) / CGFloat(columnCount)

            let columns = Array(
                repeating: GridItem(.fixed(cellSize), spacing: gridSpacing),
                count: columnCount
            )

            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(0..<viewModel.assetCount, id: \.self) { index in
                                PhotoGridCell(
                                    asset: viewModel.asset(at: index),
                                    cellSize: cellSize
                                )
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(ScrollTarget.latest)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        guard viewModel.assetCount > columnCount else {
                            return false
                        }

                        let distanceFromBottom = geometry.contentSize.height -
                            geometry.visibleRect.maxY
                        return distanceFromBottom > cellSize + gridSpacing
                    } action: { _, shouldShow in
                        withAnimation(.snappy(duration: 0.2)) {
                            showsScrollToLatestButton = shouldShow
                        }
                    }
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.topLeading, for: .alignment)
                    .background(Color(.systemBackground))

                    if showsScrollToLatestButton {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                scrollProxy.scrollTo(
                                    ScrollTarget.latest,
                                    anchor: .bottom
                                )
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial, in: Circle())
                        .accessibilityLabel("Scroll to latest photos")
                        .padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }
}

private struct PhotoGridCell: View {
    let asset: PHAsset?
    let cellSize: CGFloat

    var body: some View {
        ZStack {
            if let asset {
                NavigationLink(value: asset.localIdentifier) {
                    PhotoThumbnailView(asset: asset)
                        .frame(width: cellSize, height: cellSize)
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: cellSize, height: cellSize)
                .clipped()
                .contentShape(Rectangle())
            } else {
                Color.clear
            }
        }
        .frame(width: cellSize, height: cellSize)
        .clipped()
        .contentShape(Rectangle())
    }
}
