//
//  DraftRow.swift
//  Compost — 🌙 Sleep-On-It frozen draft row.
//
//  v0.5 refactor:
//   • Calmer rewrite is the hero (always visible). Original sits beside it
//     in a permanent two-column diff — no "Compare" toggle.
//   • Tone pills surface the variants the row actually has (parsed from
//     Rewrite Variants in the row, falling back to a single Calmer). When
//     a tone has no rewrite yet we render it disabled — no fake invocation
//     of a worker tool that doesn't exist (rephraseDraft is a proposed
//     contract in INTERFACE.md, not a live tool).
//   • Approve / Reject still call the existing reviewDraft worker tool.
//

import SwiftUI

struct DraftRow: View {
    let draft: FrozenDraft
    @ObservedObject var manager: NotchManager

    @State private var activeTone: String = ""
    @State private var isHovering = false

    private var busy: Bool {
        manager.inflight.contains(.reviewDraft(draft.id))
    }
    private var inlineError: String? { manager.draftErrors[draft.id] }
    private var rewriteForActive: String {
        draft.rewrites[activeTone] ?? draft.rewrite
    }
    private var tones: [String] {
        // Always show the canonical three so the picker is recognisable
        // even when only Calmer has a real rewrite. Extras (anything outside
        // the canonical set) get appended.
        let canonical = ["Calmer", "Crisp", "Diplomatic"]
        let extras = draft.availableTones.filter { !canonical.contains($0) }
        return canonical + extras
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            diffPane
            tonePicker
            if let err = inlineError { errorBanner(err) }
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GardenStyle.card.opacity(isHovering ? 1.6 : 1.0))
        .cornerRadius(GardenStyle.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius)
                .stroke(inlineError != nil ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onAppear { if activeTone.isEmpty { activeTone = draft.activeTone } }
        .onHover { hovering in
            if GardenStyle.reduceMotion { isHovering = hovering }
            else { withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering } }
        }
        .animation(GardenStyle.spring, value: inlineError)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !draft.frozenAt.isEmpty {
                    Text("frozen \(prettyTime(draft.frozenAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("🌙 SLEEP-ON-IT")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundColor(GardenStyle.sage300)
        }
    }

    // MARK: - Side-by-side diff

    private var diffPane: some View {
        let diff = ToneDiff(original: draft.original, calmer: rewriteForActive)
        return HStack(alignment: .top, spacing: 8) {
            sideColumn(
                title: "ORIGINAL",
                tint: GardenStyle.accentRose,
                body: diff.originalText,
                empty: draft.original.isEmpty,
                bg: GardenStyle.card,
                border: GardenStyle.hair
            )
            sideColumn(
                title: "\(activeTone.uppercased()) REWRITE",
                tint: GardenStyle.sage300,
                body: diff.calmerText,
                empty: rewriteForActive.isEmpty,
                bg: GardenStyle.accentGreen.opacity(0.08),
                border: GardenStyle.sage400.opacity(0.30)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Original on left, \(activeTone) rewrite on right")
    }

    private func sideColumn(title: String, tint: Color, body: Text, empty: Bool, bg: Color, border: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.8)
                .foregroundColor(tint)
            if empty {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    body
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(bg)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cornerRadius)
                .strokeBorder(border, lineWidth: 0.5)
        )
        .cornerRadius(GardenStyle.cornerRadius)
    }

    // MARK: - Tone picker

    private var tonePicker: some View {
        HStack(spacing: 6) {
            Text("Tone")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(tones, id: \.self) { t in
                tonePill(t)
            }
            Spacer()
        }
    }

    private func tonePill(_ tone: String) -> some View {
        let isActive = tone == activeTone
        let hasRewrite = draft.rewrites[tone]?.isEmpty == false
        return Button {
            guard hasRewrite else { return }
            activeTone = tone
        } label: {
            Text(tone)
                .font(.caption2.weight(.medium))
                .foregroundColor(toneColor(active: isActive, hasRewrite: hasRewrite))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(toneBg(active: isActive, hasRewrite: hasRewrite))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(toneBorder(active: isActive, hasRewrite: hasRewrite), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!hasRewrite)
        .help(hasRewrite
              ? "Show the \(tone) rewrite"
              : "No \(tone) rewrite available — needs the rephraseDraft worker tool")
        .accessibilityLabel("Tone \(tone), \(isActive ? "selected" : (hasRewrite ? "available" : "unavailable"))")
    }

    private func toneColor(active: Bool, hasRewrite: Bool) -> Color {
        if !hasRewrite { return GardenStyle.ink4 }
        if active      { return GardenStyle.sage300 }
        return GardenStyle.ink2
    }
    private func toneBg(active: Bool, hasRewrite: Bool) -> Color {
        if !hasRewrite { return GardenStyle.card }
        if active      { return GardenStyle.sage400.opacity(0.20) }
        return GardenStyle.card
    }
    private func toneBorder(active: Bool, hasRewrite: Bool) -> Color {
        if active      { return GardenStyle.sage400.opacity(0.40) }
        if !hasRewrite { return GardenStyle.hair }
        return GardenStyle.hair
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer()
            ghostButton("Keep mine", busy: busy) {
                Task { await manager.reviewDraft(draftId: draft.id, approve: false) }
            }
            primaryButton("✓ Use \(activeTone.lowercased())", busy: busy) {
                Task { await manager.reviewDraft(draftId: draft.id, approve: true) }
            }
        }
    }

    private func ghostButton(_ label: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini) }
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(GardenStyle.cornerRadius)
            .opacity(busy ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Reviewing" : label)
    }

    private func primaryButton(_ label: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini).tint(.white) }
                Text(label).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(.white)
            .background(GardenStyle.accentGreen)
            .cornerRadius(GardenStyle.cornerRadius)
            .opacity(busy ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Approving rewrite" : label)
    }

    // MARK: - Error banner

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.top, 1)
            Text(err)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(3)
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
        .cornerRadius(GardenStyle.cornerRadius)
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

// MARK: - Tone diff (unchanged from v0.3 — still the cleanest single-pass diff)

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
        if inOther { return Text(word) }

        let isShout = kind == .removed
            && word.count >= 4
            && word == word.uppercased()
            && word.contains(where: { $0.isLetter })

        if isShout {
            return Text(word)
                .foregroundColor(GardenStyle.accentRose)
                .fontWeight(.semibold)
                .strikethrough()
        }

        let isLong = word.count >= 3
        let isStopword = stopwords.contains(lc)
        if !isLong || isStopword { return Text(word) }

        switch kind {
        case .removed:
            return Text(word).foregroundColor(GardenStyle.accentRose.opacity(0.85))
        case .added:
            return Text(word)
                .foregroundColor(GardenStyle.sage300)
                .fontWeight(.semibold)
        }
    }
}
