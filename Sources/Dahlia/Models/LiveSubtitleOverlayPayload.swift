import Foundation

struct LiveSubtitleOverlayPayload: Equatable {
    struct Entry: Equatable {
        let primaryText: String
        let secondaryText: String?
    }

    let entries: [Entry]

    static func latest(
        from segments: [TranscriptSegment],
        sourceMode: LiveSubtitleSourceMode = .includeMicrophone,
        transcriptionLocaleIdentifier: String,
        translationEnabled: Bool,
        targetLanguageIdentifier: String,
        maxEntries: Int
    ) -> Self? {
        let clampedMaxEntries = max(1, maxEntries)
        let showsTranslation = translationEnabled && TranscriptTranslationLanguage.shouldTranslate(
            transcriptionLocaleIdentifier: transcriptionLocaleIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier
        )

        let validSegments = segments.compactMap { segment -> (segment: TranscriptSegment, entry: Entry)? in
            guard sourceMode.includesSpeakerLabel(segment.speakerLabel) else { return nil }
            guard let primaryText = segment.displayText.nilIfBlank else { return nil }
            return (
                segment,
                Entry(
                    primaryText: primaryText,
                    secondaryText: showsTranslation ? segment.displayTranslatedText : nil
                )
            )
        }

        guard !validSegments.isEmpty else { return nil }

        if let latestUnconfirmedIndex = validSegments.lastIndex(where: { !$0.segment.isConfirmed }) {
            var selectedIndices = [latestUnconfirmedIndex]
            var candidateIndex = latestUnconfirmedIndex - 1

            while candidateIndex >= 0, selectedIndices.count < clampedMaxEntries {
                selectedIndices.append(candidateIndex)
                candidateIndex -= 1
            }

            let entries = selectedIndices
                .sorted()
                .map { validSegments[$0].entry }
            return Self(entries: entries)
        }

        let entries = validSegments
            .suffix(clampedMaxEntries)
            .map(\.entry)
        return Self(entries: Array(entries))
    }
}
