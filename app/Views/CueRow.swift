//
//  CueRow.swift
//  Compost — ☀ Up next prep card on the dark notch surface.
//

import SwiftUI

struct CueRow: View {
    let cue: CueCard
    @ObservedObject var manager: NotchManager

    @State private var checkedItems: Set<String> = []
    @State private var snoozedMinutes: Int = 0

    private var isImminent: Bool { cue.minutesUntilNext > 0 && cue.minutesUntilNext < 10 }
    private var isCritical: Bool { cue.minutesUntilNext > 0 && cue.minutesUntilNext < 5 }
    private var displayMinutes: Int { max(0, cue.minutesUntilNext + snoozedMinutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow
            titleRow
            if !cue.calmCue.isEmpty { bodyLine }
            if !cue.bulletItems.isEmpty { checklist }
            actionRow
            metaRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GardenStyle.card)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius)
                .strokeBorder(isImminent ? GardenStyle.accentAmber.opacity(0.4) : GardenStyle.hair, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Up next: \(cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading)")
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Text("☀ UP NEXT")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundColor(GardenStyle.sage300)
            if !cue.currentTimeLabel().isEmpty {
                Text("· \(cue.currentTimeLabel())")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(GardenStyle.ink3)
            }
            Spacer()
        }
    }

    // MARK: - Title + countdown

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(GardenStyle.ink)
                .lineLimit(1)
            Spacer()
            if cue.minutesUntilNext > 0 || snoozedMinutes > 0 {
                countdownPill
            }
        }
    }

    private var countdownPill: some View {
        let pretty = CueCard.formatMinutes(displayMinutes)
        let label = snoozedMinutes > 0 ? "in \(pretty) (snoozed +\(snoozedMinutes)m)" : "in \(pretty)"
        return Text(label)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundColor(isImminent ? GardenStyle.accentAmber : GardenStyle.sage300)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((isImminent ? GardenStyle.accentAmber : GardenStyle.sage400).opacity(0.16))
            )
            .overlay(
                Capsule().strokeBorder(
                    (isImminent ? GardenStyle.accentAmber : GardenStyle.sage400).opacity(0.32),
                    lineWidth: 0.5
                )
            )
            .modifier(PulseScaleModifier(active: isCritical))
            .accessibilityLabel("In \(pretty)")
    }

    // MARK: - Body line

    private var bodyLine: some View {
        Text(cue.calmCue)
            .font(.system(size: 12.5, weight: .regular))
            .foregroundColor(GardenStyle.ink2)
            .lineSpacing(1.5)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Prep checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(cue.bulletItems, id: \.self) { item in
                checklistRow(item)
            }
        }
    }

    private func checklistRow(_ item: String) -> some View {
        let isChecked = checkedItems.contains(item)
        return Button {
            if isChecked { checkedItems.remove(item) } else { checkedItems.insert(item) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isChecked ? GardenStyle.accentGreen : GardenStyle.ink4, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isChecked ? GardenStyle.accentGreen : .clear)
                        )
                        .frame(width: 14, height: 14)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 3)
                Text(item)
                    .font(.system(size: 12.5))
                    .foregroundColor(isChecked ? GardenStyle.ink3 : GardenStyle.ink2)
                    .strikethrough(isChecked, color: GardenStyle.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Prep: \(item)")
        .accessibilityHint(isChecked ? "Checked, tap to uncheck" : "Tap to mark done")
    }

    // MARK: - Actions (pill-shaped)

    private var actionRow: some View {
        HStack(spacing: GardenStyle.actionRowGap) {
            actionPill(label: "↗ Open in Notion", kind: .primary, action: openSource)
            actionPill(
                label: snoozedMinutes > 0 ? "Snoozed +\(snoozedMinutes)m" : "Snooze 5m",
                kind: .ghost
            ) {
                snoozedMinutes += 5
            }
            .disabled(snoozedMinutes >= 30)
            actionPill(label: "Ask Compost ↗", kind: .muted) {
                Task { await manager.openScene(.voice) }
            }
            Spacer()
        }
    }

    private enum CueActionKind { case primary, ghost, muted }

    private func actionPill(label: String, kind: CueActionKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(
                    kind == .primary ? .white :
                    kind == .muted   ? GardenStyle.ink3 :
                                       GardenStyle.ink
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        kind == .primary ? GardenStyle.accentGreen :
                        kind == .ghost   ? Color.white.opacity(0.08) :
                                           Color.clear
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meta row

    private var metaRow: some View {
        HStack(spacing: 6) {
            if isFromAgentInbox {
                Label("from Agent Briefing Inbox", systemImage: "tray")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(GardenStyle.sage300)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(GardenStyle.sage400.opacity(0.14)))
            }
            Spacer()
            if !cleanSource.isEmpty {
                Text("[!cue] · \(cleanSource)")
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink3)
                    .lineLimit(1)
            }
        }
    }

    /// Strip the user-visible "[!cue]" marker so the meta row reads
    /// "[!cue] · Agent Briefing Inbox" instead of the duplicated
    /// "[!cue] · [!cue] Agent Briefing Inbox" we used to see.
    private var cleanSource: String {
        cue.sourceTitle
            .replacingOccurrences(of: "[!cue]", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var isFromAgentInbox: Bool {
        let t = cue.sourceTitle.lowercased()
        return t.contains("agent briefing inbox") || t.contains("[!cue]")
    }

    private func openSource() {
        let id = cue.sourcePageId.replacingOccurrences(of: "-", with: "")
        guard !id.isEmpty, let url = URL(string: "notion://www.notion.so/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct PulseScaleModifier: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && on ? 1.04 : 1.0)
            .animation(active ? GardenStyle.pulse : .default, value: on)
            .onAppear { if active { on.toggle() } }
            .onChange(of: active) { newValue in on = newValue }
    }
}
