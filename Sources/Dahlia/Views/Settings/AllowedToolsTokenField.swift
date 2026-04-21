import SwiftUI

struct AllowedToolsTokenField: View {
    @Binding var text: String

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private static let containerShape = RoundedRectangle(cornerRadius: 16)
    private static let tokenDelimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(tokens, id: \.self) { token in
                AllowedToolTokenChip(token: token) {
                    removeToken(token)
                }
            }

            TextField(L10n.agentAllowedToolsPlaceholder, text: $draft)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(minWidth: 120, alignment: .leading)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, newValue in
                    guard !newValue.isEmpty, newValue.contains(where: Self.isTokenDelimiter) else { return }
                    appendTokens(from: newValue)
                    draft = ""
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            Self.containerShape
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay {
            Self.containerShape
                .stroke(isFocused ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: isFocused ? 2 : 1)
        }
        .contentShape(Self.containerShape)
        .onTapGesture {
            isFocused = true
        }
        .accessibilityElement(children: .contain)
    }

    private var tokens: [String] {
        Self.normalizedTokens(from: text)
    }

    private func commitDraft() {
        appendTokens(from: draft)
        draft = ""
    }

    private func appendTokens(from rawText: String) {
        let appendedTokens = Self.normalizedTokens(from: rawText)
        guard !appendedTokens.isEmpty else { return }
        let currentTokens = tokens
        var seen = Set(currentTokens)
        let newTokens = appendedTokens.filter { seen.insert($0).inserted }
        guard !newTokens.isEmpty else { return }
        text = (currentTokens + newTokens).joined(separator: " ")
    }

    private func removeToken(_ token: String) {
        text = tokens.filter { $0 != token }.joined(separator: " ")
    }

    private static func normalizedTokens(from rawText: String) -> [String] {
        var seen = Set<String>()
        return rawText
            .components(separatedBy: tokenDelimiters)
            .compactMap { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
                return trimmed
            }
    }

    private static func isTokenDelimiter(_ character: Character) -> Bool {
        character.isWhitespace || character == ","
    }
}

private struct AllowedToolTokenChip: View {
    let token: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(token)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.agentAllowedToolsRemoveToken(token)))
    }
}
