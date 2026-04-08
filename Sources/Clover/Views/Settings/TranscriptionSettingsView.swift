import Speech
import SwiftUI

/// 設定画面「文字起こし」タブ。認識言語の表示フィルタを管理する。
struct TranscriptionSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var supportedLocales: [Locale] = []
    @State private var isLoadingLocales = false
    @State private var localeSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.transcription)
                .font(.title)
                .fontWeight(.bold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

        Form {
            Section {
                if isLoadingLocales {
                    ProgressView(L10n.loadingLanguages)
                        .font(.caption)
                } else {
                    TextField(L10n.searchLanguages, text: $localeSearchText)
                        .textFieldStyle(.roundedBorder)

                    let searchedLocales = searchFilteredLocales
                    if searchedLocales.isEmpty {
                        Text(L10n.noMatchingLanguages)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(searchedLocales, id: \.identifier) { locale in
                                    let id = locale.identifier
                                    let isEnabled = settings.isLocaleEnabled(id)
                                    Button {
                                        toggleLocale(id)
                                    } label: {
                                        HStack {
                                            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isEnabled ? .accentColor : .secondary)
                                            Text(locale.localizedString(forIdentifier: id) ?? id)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text(id)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 200)
                    }

                    HStack {
                        let enabledCount = settings.enabledLocaleIdentifiers.count
                        Text(enabledCount == 0
                            ? L10n.allLanguagesShown
                            : L10n.languagesSelected(enabledCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !settings.enabledLocaleIdentifiers.isEmpty {
                            Button(L10n.showAll) {
                                settings.enabledLocaleIdentifiers = []
                            }
                            .font(.caption)
                        }
                    }
                }
            } footer: {
                Text(L10n.displayLanguagesDescription)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await loadSupportedLocales()
        }

        } // VStack
    }

    // MARK: - Private

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

    private func loadSupportedLocales() async {
        isLoadingLocales = true
        let locales = await SpeechTranscriber.supportedLocales
        supportedLocales = locales.sortedByLocalizedName()
        isLoadingLocales = false
    }
}
