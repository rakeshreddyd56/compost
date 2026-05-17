//
//  CueRow.swift
//  Compost — ☀ Up next prep card driven by cueCards rows.
//
//  v0.5 refactor: the row is now a structured prep card.
//   • Hero time strip (current time + minutes-until-next pill)
//   • Calm rephrasing line from cueCards.Calm Cue
//   • Local prep checklist parsed from cueCards.Current Bullets
//     (toggles are local-only — we never write back to Notion from here)
//   • Action row: Open in Notion · Snooze 5m
//

import SwiftUI

struct CueRow: View {
    let cue: CueCard
    @ObservedObject var manager: NotchManager

    @State private var checkedItems: Set<String> = []
    @State private var snoozedMinutes: Int = 0

    private var isImminent: Bool { cue.minutesUntilNext > 0 && cue.minutesUntilNext < 10 }
    private var isCritical: Bool { cue.minutesUntilNext > 0 && cue.minutesUntilNext < 5 }

    private var displayMinutes: Int {
        max(0, cue.minutesUntilNext + snoozedMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow
            timeStrip
            if !cue.calmCue.isEmpty { bodyLine }
            if !cue.bulletItems.isEmpty { checklist }
            actionRow
            metaRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GardenStyle.accentGreen.opacity(0.10))
        .cornerRadius(GardenStyle.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius)
                .strokeBorder(isImminent ? GardenStyle.accentAmber.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Up next: \(cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading)")
    }

    // MARK: - Eyebrow + title

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Text("☀ UP NEXT")
                .font(.caption2.weight(.bold))
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

    // MARK: - Time strip

    private var timeStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if cue.minutesUntilNext > 0 {
                countdownPill
            }
        }
    }

    private var countdownPill: some View {
        let label = snoozedMinutes > 0
            ? "in \(displayMinutes)m (snoozed +\(snoozedMinutes))"
            : "in \(displayMinutes)m"
        return Text(label)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundColor(isImminent ? GardenStyle.accentAmber : GardenStyle.sage300)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((isImminent ? GardenStyle.accentAmber : GardenStyle.sage400).opacity(0.18))
            )
            .overlay(
                Capsule().strokeBorder(
                    (isImminent ? GardenStyle.accentAmber : GardenStyle.sage400).opacity(0.30),
                    lineWidth: 0.5
                )
            )
            .modifier(PulseScaleModifier(active: isCritical))
            .accessibilityLabel("In \(displayMinutes) minutes")
    }

    // MARK: - Body line

    private var bodyLine: some View {
        Text(cue.calmCue)
            .font(.callout)
            .foregroundColor(.primary.opacity(0.85))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Prep checklist (local-only state)

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
                .padding(.top, 2)
                Text(item)
                    .font(.caption)
                    .strikethrough(isChecked, color: GardenStyle.ink4)
                    .foregroundColor(isChecked ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Prep: \(item)")
        .accessibilityHint(isChecked ? "Checked, tap to uncheck" : "Tap to mark done")
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: GardenStyle.actionRowGap) {
            actionPill(label: "↗ Open in Notion", primary: true, action: openSource)
            actionPill(label: snoozedMinutes > 0 ? "Snoozed +\(snoozedMinutes)m" : "Snooze 5m", primary: false) {
                snoozedMinutes += 5
            }
            .disabled(snoozedMinutes >= 30)
            Spacer()
        }
    }

    private func actionPill(label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(primary ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(primary ? GardenStyle.accentGreen : Color.secondary.opacity(0.15))
                .cornerRadius(GardenStyle.cornerRadius)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meta row

    private var metaRow: some View {
        HStack {
            Spacer()
            Text("[!cue] · \(cue.sourceTitle)")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
                .lineLimit(1)
        }
    }

    // MARK: - Open source

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
