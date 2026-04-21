import Foundation
import Translation
import os

actor TranscriptTranslationService {
    private let logger = Logger(subsystem: "com.dahlia", category: "TranscriptTranslation")
    private let sourceLanguage = Locale.Language(languageCode: .english)
    private let targetLanguage = Locale.Language(languageCode: .japanese)

    private var availabilityStatus: LanguageAvailability.Status?

    func translateToJapanese(_ text: String) async -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        guard await isSupportedLanguagePair else { return nil }

        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)

        do {
            let response = try await session.translate(trimmedText)
            return response.targetText.nilIfBlank
        } catch {
            logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private var isSupportedLanguagePair: Bool {
        get async {
            if let availabilityStatus {
                return availabilityStatus != .unsupported
            }

            let availability = LanguageAvailability()
            let status = await availability.status(from: sourceLanguage, to: targetLanguage)
            availabilityStatus = status
            if status == .unsupported {
                logger.warning("English to Japanese translation is unsupported on this system")
            }
            return status != .unsupported
        }
    }
}
