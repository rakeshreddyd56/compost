//
//  DraftRow.swift
//  Compost — Sleep-On-It draft row with tone-diff side-by-side
//

import SwiftUI

struct DraftRow: View {
    let draft: FrozenDraft
    @ObservedObject var manager: NotchManager
    @State private var isHovering = false
    @State private var showSideBySide = false

    private var busy: Bool {
        manager.inflight.contains(.reviewDraft(draft.id))
    }

    private var inlineError: String? {
        manager.draftErrors[draft.id]
    }

    /// True when the Worker's "calmer" rewrite is the same text as the user's
    /// original (after whitespace normalization). Common when the late-night
    /// edit was already calm — the rewrite is a no-op. We surface this
    /// truthfully so the user doesn't approve a change that won't visibly
    /// alter their Notion page.
    private var alreadyCalm: Bool {
        let a = Self.normalize(draft.original)
        let b = Self.normalize(draft.rewrite)
        return !a.isEmpty && a == b
    }

    private static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            // Collapsed: lead with the calmer rewrite — that's the offer
            // the user is being asked to accept. Original lives one tap away.
            if showSideBySide {
                sideBySide
            } else {
                calmerHero
            }
            if let err = inlineError { errorBanner(err) }
            actionButtons
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(isHovering ? 0.08 : 0.05))
        .cornerRadius(GardenStyle.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cornerRadius)
                .stroke(inlineError != nil ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            if GardenStyle.reduceMotion { isHovering = hovering }
            else { withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering } }
        }
        .animation(GardenStyle.spring, value: showSideBySide)
        .animation(GardenStyle.spring, value: inlineError)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(draft.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if alreadyCalm { alreadyCalmBadge }
                }
                if !draft.frozenAt.isEmpty {
                    Text("frozen \(prettyTime(draft.frozenAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: { showSideBySide.toggle() }) {
                HStack(spacing: 3) {
                    Text(showSideBySide ? "Hide compare" : "Compare")
                        .font(.caption2.weight(.medium))
                    Image(systemName: showSideBySide ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show original vs. calmer rewrite side by side")
            .accessibilityLabel(showSideBySide ? "Hide side-by-side" : "Show side-by-side comparison")
        }
    }

    private var alreadyCalmBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Already calm")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundColor(GardenStyle.accentGreen)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(GardenStyle.accentGreen.opacity(0.12))
        .clipShape(Capsule())
        .help("Original and calmer rewrite are the same — approving won't change your Notion page.")
        .accessibilityLabel("Already calm — rewrite matches original")
    }

    // MARK: - Collapsed hero: just the calmer rewrite

    private var calmerHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Calmer rewrite", systemImage: "leaf.fill")
                .font(.caption2.weight(.semibold))
                .foregroundColor(GardenStyle.accentGreen)
            Text(draft.rewrite.isEmpty ? "—" : draft.rewrite)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GardenStyle.accentGreen.opacity(0.08))
        .cornerRadius(GardenStyle.cornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calmer rewrite: \(draft.rewrite)")
    }

    // MARK: - Expanded side-by-side with tone diff

    private var sideBySide: some View {
        let diff = ToneDiff(original: draft.original, calmer: draft.rewrite)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                sideColumn(
                    title: "Original",
                    tint: .red,
                    body: diff.originalText,
                    empty: draft.original.isEmpty
                )
                sideColumn(
                    title: "Calmer",
                    tint: GardenStyle.accentGreen,
                    body: diff.calmerText,
                    empty: draft.rewrite.isEmpty
                )
            }
            if !draft.sourcePageId.isEmpty {
                openSourceLink
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Original on left, calmer rewrite on right")
    }

    /// Direct link to the Notion source page so the user can confirm which
    /// document they're actually about to mutate before clicking Use calmer.
    private var openSourceLink: some View {
        Button(action: openSource) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                Text("Open source")
                    .font(.caption)
                    .underline()
            }
            .foregroundColor(GardenStyle.accentGreen)
        }
        .buttonStyle(.plain)
        .help("Open the source Notion page that this draft was extracted from")
        .accessibilityLabel("Open the source Notion page")
    }

    private func openSource() {
        let id = draft.sourcePageId.replacingOccurrences(of: "-", with: "")
        guard !id.isEmpty, let url = URL(string: "notion://www.notion.so/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func sideColumn(title: String, tint: Color, body: Text, empty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(tint)
            if empty {
                Text("—").font(.caption).foregroundColor(.secondary)
            } else {
                body
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.06))
        .cornerRadius(GardenStyle.cornerRadius)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                keepMineButton
                useCalmerButton
                Spacer()
            }
            if busy {
                LongActionHint(start: manager.inflightStartedAt[.reviewDraft(draft.id)])
            }
        }
    }

    private var keepMineButton: some View {
        Button(action: {
            Task { await manager.reviewDraft(draftId: draft.id, approve: false) }
        }) {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini) }
                Text("Keep mine")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(GardenStyle.cornerRadius)
            .opacity(busy ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Reviewing draft" : "Keep my original draft")
        .help("Reject the rewrite and keep your original")
    }

    private var useCalmerButton: some View {
        // When the rewrite already matches the original, Use calmer would
        // approve a no-op write to the Notion page. Disable it and relabel
        // so the user isn't tricked into thinking they'll see a change.
        let disabled = busy || alreadyCalm
        let label = alreadyCalm ? "Already calm" : (busy ? "Use calmer" : "Use calmer")
        return Button(action: {
            Task { await manager.reviewDraft(draftId: draft.id, approve: true) }
        }) {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini).tint(.white) }
                else if alreadyCalm { Image(systemName: "checkmark.seal.fill").font(.caption2) }
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(.white)
            .background(alreadyCalm ? GardenStyle.accentGreen.opacity(0.45) : GardenStyle.accentGreen)
            .cornerRadius(GardenStyle.cornerRadius)
            .opacity(busy ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(
            alreadyCalm ? "Already calm — no rewrite needed"
                        : (busy ? "Reviewing draft" : "Use the calmer rewrite")
        )
        .help(
            alreadyCalm
                ? "Original and calmer rewrite are identical — approving wouldn't change your Notion page."
                : "Approve the rewrite — Notion page gets updated"
        )
    }

    // MARK: - Per-draft error banner

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.top, 1)
            Text(err)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
        .cornerRadius(GardenStyle.cornerRadius)
        .help(err)
        .accessibilityLabel("Review failed: \(err)")
    }

    // MARK: - Helpers

    private func prettyTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return rel.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}

// MARK: - Tone diff
//
// Lightweight word-level "what changed" highlighter. No diff library: just
// case-insensitive set difference on word tokens.
//
//   • On the Original side, any word present in original but not in calmer
//     is rendered red. Words that are ALSO ALL-CAPS shouts (length ≥ 4) get
//     strikethrough — that's the signature "I am REALLY UPSET" move that the
//     Sleep-On-It pass exists to soften.
//   • On the Calmer side, any word present in calmer but not in original is
//     rendered in sage + semibold. That's the gentler phrasing the rewrite
//     introduced.
//
// Short connective words (length < 3) and common stopwords are skipped so the
// highlight doesn't fire on "and / the / is / to" every line.

struct ToneDiff {
    let originalText: Text
    let calmerText: Text

    init(original: String, calmer: String) {
        let originalTokens = Self.tokens(in: original)
        let calmerTokens = Self.tokens(in: calmer)

        self.originalText = Self.render(
            source: original,
            otherWordsLowercased: calmerTokens.lowercasedSet,
            kind: .removed
        )
        self.calmerText = Self.render(
            source: calmer,
            otherWordsLowercased: originalTokens.lowercasedSet,
            kind: .added
        )
    }

    private enum Kind { case removed, added }

    private struct TokenSet {
        let words: [String]
        let lowercasedSet: Set<String>
    }

    private static let stopwords: Set<String> = [
        "the","a","an","and","or","but","of","to","in","on","at","for","by",
        "with","is","am","are","was","were","be","been","being","this","that",
        "these","those","it","its","i","im","ive","id","ill","you","your","we",
        "our","us","they","their","them","not","no","so","do","does","did",
        "have","has","had","will","would","can","could","should","may","might",
        "as","if","then","than","there","here","just","yet","also","too","very"
    ]

    private static func tokens(in text: String) -> TokenSet {
        let words = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0) }
        let set = Set(words.map { $0.lowercased() })
        return TokenSet(words: words, lowercasedSet: set)
    }

    private static func render(
        source: String,
        otherWordsLowercased: Set<String>,
        kind: Kind
    ) -> Text {
        // Walk the source character-by-character so punctuation, spaces, and
        // newlines render exactly as authored — we only style the word runs.
        var result = Text("")
        var current = ""
        var inWord = false

        func flush() {
            guard !current.isEmpty else { return }
            if inWord {
                result = result + style(word: current, kind: kind, otherWordsLowercased: otherWordsLowercased)
            } else {
                result = result + Text(current)
            }
            current = ""
        }

        for ch in source {
            let isWordChar = ch.isLetter || ch.isNumber || ch == "'"
            if isWordChar != inWord {
                flush()
                inWord = isWordChar
            }
            current.append(ch)
        }
        flush()
        return result
    }

    private static func style(
        word: String,
        kind: Kind,
        otherWordsLowercased: Set<String>
    ) -> Text {
        let lc = word.lowercased()
        let inOther = otherWordsLowercased.contains(lc)
        if inOther { return Text(word) }  // unchanged either way

        // ALL-CAPS shout detection runs BEFORE stopword filtering on the
        // removed side. "WILL" / "WHOLE" / "FAIL" are stopword-ish in lower
        // case but the whole point of Sleep-On-It is to soften shouting,
        // so we want them highlighted even if normally we'd skip them.
        let isShout = kind == .removed
            && word.count >= 4
            && word == word.uppercased()
            && word.contains(where: { $0.isLetter })

        if isShout {
            return Text(word)
                .foregroundColor(.red)
                .fontWeight(.semibold)
                .strikethrough()
        }

        let isLong = word.count >= 3
        let isStopword = stopwords.contains(lc)
        if !isLong || isStopword { return Text(word) }

        switch kind {
        case .removed:
            return Text(word).foregroundColor(.red.opacity(0.85))
        case .added:
            return Text(word)
                .foregroundColor(GardenStyle.accentGreen)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    let mockPage = NotionPage(
        id: "123",
        properties: [:],
        last_edited_time: nil,
        archived: false
    )
    return DraftRow(
        draft: FrozenDraft(mockPage)!,
        manager: NotchManager.preview
    )
}
