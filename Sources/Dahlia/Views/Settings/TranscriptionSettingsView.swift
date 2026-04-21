import Speech
import SwiftUI

/// 設定画面「文字起こし」タブ。認識言語の表示フィルタを管理する。
struct TranscriptionSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var supportedLocales: [Locale] = []
    @State private var isLoadingLocales = false
    @State private var localeSearchText = ""

    var body: some View {
        SettingsPage {
            SettingsSection(title: L10n.transcriptTranslation) {
                SettingsCard {
                    SettingsToggleRow(
                        title: L10n.transcriptTranslation,
                        description: L10n.transcriptTranslationDescription,
                        isOn: $settings.transcriptTranslationEnabled
                    )
                }
            }

            SettingsSection(
                title: L10n.displayLanguages,
                description: L10n.displayLanguagesDescription
            ) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField(L10n.searchLanguages, text: $localeSearchText)
                            .textFieldStyle(.roundedBorder)

                        if isLoadingLocales {
                            ProgressView(L10n.loadingLanguages)
                        } else {
                            localeSelectionList
                            localeSelectionFooter
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task {
            await loadSupportedLocales()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var localeSelectionList: some View {
        let searchedLocales = searchFilteredLocales
        if searchedLocales.isEmpty {
            Text(L10n.noMatchingLanguages)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(searchedLocales, id: \.identifier) { locale in
                        localeRow(for: locale)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220, maxHeight: 280)
        }
    }

    private var localeSelectionFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            let enabled = settings.enabledLocaleIdentifiers
            Text(
                enabled.isEmpty
                    ? L10n.allLanguagesShown
                    : L10n.languagesSelected(enabled.count)
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()

            if !enabled.isEmpty {
                Button(L10n.uncheckAll) {
                    settings.enabledLocaleIdentifiers = []
                }
            }

            if enabled.count != supportedLocales.count {
                Button(L10n.showAll) {
                    settings.enabledLocaleIdentifiers = Set(supportedLocales.map(\.identifier))
                }
            }
        }
    }

    private var searchFilteredLocales: [Locale] {
        guard !localeSearchText.isEmpty else { return supportedLocales }
        let query = localeSearchText.lowercased()
        return supportedLocales.filter { locale in
            let name = locale.localizedString(forIdentifier: locale.identifier) ?? ""
            return name.lowercased().contains(query)
                || locale.identifier.lowercased().contains(query)
        }
    }

    private func toggleLocale(_ identifier: String) {
        var enabled = settings.enabledLocaleIdentifiers
        if enabled.isEmpty {
            enabled = Set(supportedLocales.map(\.identifier))
            enabled.remove(identifier)
        } else if enabled.contains(identifier) {
            enabled.remove(identifier)
            if enabled.isEmpty { /* そのまま空セットでOK */ }
        } else {
            enabled.insert(identifier)
        }
        settings.enabledLocaleIdentifiers = enabled
    }

    private func localeRow(for locale: Locale) -> some View {
        let identifier = locale.identifier
        let isEnabled = settings.isLocaleEnabled(identifier)
        return Button {
            toggleLocale(identifier)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)

                Text(locale.localizedString(forIdentifier: identifier) ?? identifier)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(identifier)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadSupportedLocales() async {
        isLoadingLocales = true
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = locales.sortedByLocalizedName()
        isLoadingLocales = false
    }
}
