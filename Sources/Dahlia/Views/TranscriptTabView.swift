import SwiftUI

struct TranscriptTabView: View {
    private enum ScrollMetrics {
        static let bottomAnchorID = "transcript-bottom"
        static let followThreshold: CGFloat = 32
    }

    private enum WindowMetrics {
        static let initialWindowSize = 150
        static let loadMoreCount = 100
    }

    @ObservedObject var store: TranscriptStore
    let isListening: Bool
    let showsRecordingIndicator: Bool
    let showsTranslatedText: Bool

    @State private var shouldFollowLatest = true
    @State private var windowSize = WindowMetrics.initialWindowSize

    /// ForEach の ID 照合対象を制限するため、末尾 windowSize 件のみ返す。
    private var windowedSegments: ArraySlice<TranscriptSegment> {
        let segments = store.segments
        guard segments.count > windowSize else { return segments[...] }
        return segments.suffix(windowSize)
    }

    /// 配列確保なしでウィンドウ内のセグメント数を返す。
    private var windowedSegmentCount: Int {
        min(store.segments.count, windowSize)
    }

    private var hasMoreAbove: Bool {
        store.segments.count > windowSize
    }

    var body: some View {
        Group {
            if store.segments.isEmpty, !isListening {
                ContentUnavailableView {
                    Label(L10n.transcript, systemImage: "waveform.badge.microphone")
                } description: {
                    Text("文字起こしはまだありません")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcriptScrollView
            }
        }
    }

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if hasMoreAbove {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .onAppear {
                                loadMoreSegments()
                            }
                    }

                    ForEach(windowedSegments) { segment in
                        TranscriptRowView(
                            segment: segment,
                            showsTranslatedText: showsTranslatedText
                        )
                        .equatable()
                    }

                    if showsRecordingIndicator {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text(L10n.recognizing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.leading, 68)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollMetrics.bottomAnchorID)
                }
                .padding(8)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height
                    - geometry.contentOffset.y
                    - geometry.containerSize.height
                return distanceFromBottom <= ScrollMetrics.followThreshold
            } action: { _, isNearBottom in
                shouldFollowLatest = isNearBottom
            }
            .onChange(of: windowedSegmentCount) { oldCount, newCount in
                guard newCount > oldCount, shouldFollowLatest else { return }
                scrollToBottom(using: proxy)
            }
            .onChange(of: shouldFollowLatest) { _, isFollowing in
                if isFollowing {
                    windowSize = WindowMetrics.initialWindowSize
                }
            }
        }
    }

    private func loadMoreSegments() {
        windowSize = min(windowSize + WindowMetrics.loadMoreCount, store.segments.count)
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(ScrollMetrics.bottomAnchorID, anchor: .bottom)
        }
    }
}
