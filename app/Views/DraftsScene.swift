//
//  DraftsScene.swift
//  Compost — focused 🌙 Drafts surface matching prototype scene 02.
//
//  Three frozen drafts as selectable rows at the top, then a single
//  ORIGINAL | TONE REWRITE diff pane for the active draft, then the
//  tone picker + "↻ rephrase" + Keep mine / Use {tone} actions.
//

import SwiftUI

struct DraftsScene: View {
    @ObservedObject var manager: NotchManager

    @State private var activeId: String? = nil
    @State private var activeTone: String = "Calmer"

    private var drafts: [FrozenDraft] { manager.summary.drafts }
    private var active: FrozenDraft? {
        guard !drafts.isEmpty else { return nil }
        if let id = activeId, let found = drafts.first(where: { $0.id == id }) {
            return found
        }
        return drafts.first
    }

    var body: some View {
        SceneShell(
            manager: manager,
            eyebrow: "🌙 SLEEP-ON-IT · \(drafts.count) FROZEN",
            title: "Morning review",
            mood: .nudging,
            wide: true
        ) {
            if drafts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    draftList
                    if let active = active {
                        diffPane(active)
                        toneAndActions(active)
                        if let err = manager.draftErrors[active.id] {
                            errorBanner(err)
                        }
                    }
                }
            }
        }
        .onChange(of: drafts.map(\.id).joined()) { _ in
            // Reset active when the list shifts (eg after a poll removes a row).
            if let id = activeId, !drafts.contains(where: { $0.id == id }) {
                activeId = nil
            }
        }
        .onAppear {
            if activeId == nil, let first = drafts.first {
                activeId = first.id
                activeTone = first.activeTone.isEmpty ? "Calmer" : first.activeTone.capitalized
            }
        }
    }

    // MARK: - Draft list (selectable rows)

    private var draftList: some View {
        VStack(spacing: 6) {
            ForEach(drafts) { draft in
                draftRowItem(draft)
            }
        }
    }

    private func draftRowItem(_ draft: FrozenDraft) -> some View {
        let isActive = (activeId ?? drafts.first?.id) == draft.id
        return Button {
            activeId = draft.id
            activeTone = draft.activeTone.isEmpty ? "Calmer" : draft.activeTone.capitalized
        } label: {
            HStack(spacing: 8) {
                Text(draft.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(GardenStyle.ink)
                    .lineLimit(1)
                Text("frozen")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(isActive ? GardenStyle.sage300 : GardenStyle.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isActive ? GardenStyle.sage400.opacity(0.18) : Color.white.opacity(0.06)))
                Spacer()
                Text(prettyTime(draft.frozenAt))
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isActive ? GardenStyle.accentGreen.opacity(0.16) : GardenStyle.card)
            .overlay(
                RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius)
                    .strokeBorder(isActive ? GardenStyle.sage400.opacity(0.5) : GardenStyle.hair, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(draft.title), frozen at \(prettyTime(draft.frozenAt))")
        .accessibilityHint("Tap to compare")
    }

    // MARK: - Diff pane

    private func diffPane(_ draft: FrozenDraft) -> some View {
        let rewrite = draft.rewrites[activeTone] ?? draft.rewrite
        let diff = ToneDiff(original: draft.original, calmer: rewrite)
        return HStack(alignment: .top, spacing: 8) {
            diffColumn(
                title: "ORIGINAL · \(prettyTime(draft.frozenAt)) you",
                rightLabel: "raw",
                tint: GardenStyle.accentRose,
                body: diff.originalText,
                empty: draft.original.isEmpty,
                bg: GardenStyle.card,
                border: GardenStyle.hair
            )
            diffColumn(
                title: "\(activeTone.uppercased()) REWRITE",
                rightLabel: toneBadge(activeTone),
                tint: GardenStyle.sage300,
                body: diff.calmerText,
                empty: rewrite.isEmpty,
                bg: GardenStyle.accentGreen.opacity(0.10),
                border: GardenStyle.sage400.opacity(0.30)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Original on left, \(activeTone) rewrite on right")
    }

    private func diffColumn(
        title: String,
        rightLabel: String,
        tint: Color,
        body: Text,
        empty: Bool,
        bg: Color,
        border: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(tint)
                Spacer()
                Text(rightLabel)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(tint.opacity(0.6))
            }
            if empty {
                Text("—")
                    .font(.caption)
                    .foregroundColor(GardenStyle.ink3)
            } else {
                ScrollView {
                    body
                        .font(.system(size: 11.5))
                        .foregroundColor(GardenStyle.ink2)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 80, maxHeight: 130)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(bg)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cornerRadius)
                .strokeBorder(border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cornerRadius))
    }

    // MARK: - Tone picker + actions

    private func toneAndActions(_ draft: FrozenDraft) -> some View {
        HStack(spacing: 6) {
            Text("Tone")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
            ForEach(["Calmer", "Crisp", "Diplomatic"], id: \.self) { t in
                tonePill(draft, tone: t)
            }
            rephrasePill(draft)
            Spacer()
            ghostPill("Keep mine", busy: isReviewBusy(draft)) {
                Task { await manager.reviewDraft(draftId: draft.id, approve: false) }
            }
            primaryPill("✓ Use \(activeTone.lowercased())", busy: isReviewBusy(draft)) {
                Task { await manager.reviewDraft(draftId: draft.id, approve: true) }
            }
        }
    }

    private func tonePill(_ draft: FrozenDraft, tone: String) -> some View {
        let isActive = tone == activeTone
        let rewrite = draft.rewrites[tone] ?? ""
        let hasRewrite = !rewrite.isEmpty
        let hasDistinctRewrite = tone == "Calmer"
            ? hasRewrite
            : hasRewrite && normalize(rewrite) != normalize(draft.rewrite)
        let busyHere = manager.inflight.contains(.rephraseDraft(draft.id, tone.lowercased()))
        let anyBusy = manager.inflight.contains(where: {
            if case .rephraseDraft(let id, _) = $0 { return id == draft.id }
            return false
        })
        return Button {
            if hasDistinctRewrite {
                activeTone = tone
            } else {
                Task {
                    await manager.rephraseDraft(draft, displayTone: tone)
                    activeTone = tone
                }
            }
        } label: {
            HStack(spacing: 4) {
                if busyHere {
                    ProgressView().controlSize(.mini).tint(GardenStyle.sage300)
                }
                Text(tone)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(
                        isActive ? GardenStyle.sage300 : (hasDistinctRewrite ? GardenStyle.ink2 : GardenStyle.ink3)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isActive ? GardenStyle.sage400.opacity(0.20) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? GardenStyle.sage400.opacity(0.40) : Color.clear,
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(anyBusy && !busyHere)
        .help(hasDistinctRewrite ? "Show the \(tone) rewrite" : "Tap to generate a distinct \(tone) rewrite")
    }

    private func toneBadge(_ tone: String) -> String {
        switch tone {
        case "Crisp": return "short/direct"
        case "Diplomatic": return "relationship-safe"
        default: return "calm"
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rephrasePill(_ draft: FrozenDraft) -> some View {
        let busy = manager.inflight.contains(where: {
            if case .rephraseDraft(let id, _) = $0 { return id == draft.id }
            return false
        })
        return Button {
            Task { await manager.rephraseDraft(draft, displayTone: activeTone) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: busy ? "ellipsis" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                Text(busy ? "…" : "rephrase")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundColor(GardenStyle.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help("Regenerate the \(activeTone) rewrite")
    }

    private func isReviewBusy(_ draft: FrozenDraft) -> Bool {
        manager.inflight.contains(.reviewDraft(draft.id))
    }

    private func ghostPill(_ label: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini).tint(GardenStyle.ink) }
                Text(label).font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(GardenStyle.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .opacity(busy ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func primaryPill(_ label: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if busy { ProgressView().controlSize(.mini).tint(.white) }
                Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundColor(.white)
            .background(Capsule().fill(GardenStyle.accentGreen))
            .opacity(busy ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - Empty + error

    private var emptyState: some View {
        VStack(spacing: 10) {
            Mascot(size: 56, mood: .calm)
            Text("Nothing frozen.")
                .font(.callout.weight(.semibold))
                .foregroundColor(GardenStyle.ink)
            Text("Sleep-On-It freezes late-night drafts into frozenDrafts; they surface here for morning review.")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(GardenStyle.accentRose)
            Text(err)
                .font(.caption2)
                .foregroundColor(GardenStyle.ink2)
                .lineLimit(3)
            Spacer()
        }
        .padding(8)
        .background(GardenStyle.accentRose.opacity(0.10))
        .cornerRadius(GardenStyle.cornerRadius)
    }

    // MARK: - Helpers

    private func prettyTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.locale = .current
        out.dateFormat = "h:mm a"
        return out.string(from: d)
    }
}
