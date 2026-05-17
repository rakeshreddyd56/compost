//
//  CueScene.swift
//  Compost — focused ☀ Cue surface matching prototype scene 01.
//
//  Hero time strip (big 30pt rounded "10:30 AM" + tabular pill),
//  conditional Gmail/Meet invite row when the source page exposes a
//  Meet URL or comma-separated attendees in the Current Bullets,
//  calm cue body with *italic markdown*, prep checklist (local-only),
//  Open in Notion / Snooze 5m / Ask Compost ↗.
//

import SwiftUI
import AppKit

struct CueScene: View {
    @ObservedObject var manager: NotchManager

    @State private var checkedItems: Set<String> = []
    @State private var snoozedMinutes: Int = 0

    private var cue: CueCard? { manager.summary.currentCue }

    var body: some View {
        SceneShell(
            manager: manager,
            eyebrow: eyebrowText,
            title: cue?.currentHeading.isEmpty == false
                ? cue!.currentHeading
                : (cue?.sourceTitle ?? "Up next"),
            mood: mascotMood
        ) {
            if let cue = cue {
                VStack(alignment: .leading, spacing: GardenStyle.expandedInnerGap) {
                    timeStrip(cue)
                    if let invite = parseInvite(from: cue) { inviteRow(invite) }
                    if !cue.calmCue.isEmpty { bodyLine(cue.calmCue) }
                    // Drop "Attendees:", "Meet:", "When:", etc — those are
                    // event metadata the invite row already shows.
                    let prepItems = cue.bulletItems.filter { !Self.isEventMetadataLine($0) }
                    if !prepItems.isEmpty { checklist(prepItems) }
                    actionRow(cue)
                    metaRow(cue)
                }
            } else {
                emptyCue
            }
        }
    }

    // MARK: - Eyebrow + mood

    private var eyebrowText: String {
        guard let cue, !cue.currentTimeLabel().isEmpty else { return "☀ UP NEXT" }
        return "☀ UP NEXT · \(cue.currentTimeLabel())"
    }

    private var mascotMood: Mascot.Mood {
        guard let cue, cue.minutesUntilNext > 0 else { return .calm }
        return cue.minutesUntilNext < 5 ? .alert : .calm
    }

    // MARK: - Hero time strip

    private func timeStrip(_ cue: CueCard) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            heroTime(cue)
            countdownPill(cue)
            Spacer()
        }
    }

    @ViewBuilder
    private func heroTime(_ cue: CueCard) -> some View {
        if let parts = splitTime(cue.currentTimeLabel()) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(parts.time)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(GardenStyle.ink)
                Text(parts.ampm)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(GardenStyle.ink3)
            }
        } else {
            // No parseable time — show heading at hero size.
            Text(cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(GardenStyle.ink)
                .lineLimit(1)
        }
    }

    private func splitTime(_ s: String) -> (time: String, ampm: String)? {
        // Expected formats: "10:30 AM" / "1:47 PM"
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private func countdownPill(_ cue: CueCard) -> some View {
        let mins = max(0, cue.minutesUntilNext + snoozedMinutes)
        let pretty = CueCard.formatMinutes(mins)
        let imminent = mins > 0 && mins < 10
        let critical = mins > 0 && mins < 5
        return Text(snoozedMinutes > 0 ? "in \(pretty) · snoozed +\(snoozedMinutes)m" : "in \(pretty)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(imminent ? GardenStyle.accentAmber : GardenStyle.sage300)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill((imminent ? GardenStyle.accentAmber : GardenStyle.sage400).opacity(0.14)))
            .overlay(Capsule().strokeBorder((imminent ? GardenStyle.accentAmber : GardenStyle.sage400).opacity(0.30), lineWidth: 0.5))
            .modifier(CuePulse(active: critical))
    }

    // MARK: - Conditional Gmail/Meet invite row

    private struct Invite {
        let attendees: [String]
        let meetUrl: URL?
        let bridgeBacked: Bool
    }

    /// Always returns an Invite when we have a cue — the row renders for
    /// every briefing so the Gmail / Meet glyphs are always visible. The
    /// content stays honest: when the cue text exposes a Meet URL or
    /// attendees, we use them; otherwise the row shows "Calendar context"
    /// + "No Meet link" placeholder.
    private func parseInvite(from cue: CueCard) -> Invite? {
        let haystack = [
            cue.calmCue,
            cue.currentBullets,
            cue.nextBullets,
            cue.currentHeading,
            cue.nextHeading,
            cue.sourceTitle,
        ].joined(separator: "\n")
        let meetUrl = Self.firstMeetURL(in: haystack)
        let attendees = Self.parseAttendees(in: haystack) ?? []
        let bridgeBacked = Self.looksLikeCalendarBridge(haystack)
        return Invite(attendees: attendees, meetUrl: meetUrl, bridgeBacked: bridgeBacked)
    }

    private static let meetRegex = try! NSRegularExpression(
        pattern: #"https?://meet\.google\.com/[A-Za-z0-9-]+"#
    )
    private static func firstMeetURL(in s: String) -> URL? {
        let r = NSRange(s.startIndex..., in: s)
        guard let m = meetRegex.firstMatch(in: s, range: r),
              let range = Range(m.range, in: s) else { return nil }
        return URL(string: String(s[range]))
    }

    private static func parseAttendees(in s: String) -> [String]? {
        // Handle the formats the Notion Agent actually writes:
        //   "Attendees: Maya, Theo"
        //   "**Attendees:** Maya, Theo, Alex"
        //   "- Attendees: Maya & Theo"
        //   "with Maya & Theo"
        //   "From Calendar: Maya, Theo"
        //   "Calendar invite to Maya and Theo"
        let lines = s.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let lc = line.lowercased()
            let looksLikeAttendeeLine =
                lc.contains("attendee") ||
                lc.contains("with ") ||
                lc.contains("from calendar") ||
                lc.contains("calendar invite") ||
                lc.contains("invitees") ||
                lc.contains("guests:")
            guard looksLikeAttendeeLine else { continue }

            // Strip everything left of the first ":" so "Attendees: A, B"
            // and "**Attendees:** A, B" both yield "A, B".
            var cleaned = line
            if let colon = cleaned.firstIndex(of: ":") {
                cleaned = String(cleaned[cleaned.index(after: colon)...])
            }
            cleaned = cleaned
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "- ", with: "", options: .anchored)
                .replacingOccurrences(of: "📧", with: "")
                .replacingOccurrences(of: "with ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "calendar invite to ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " and ", with: ", ")
                .replacingOccurrences(of: " & ", with: ", ")
                .trimmingCharacters(in: .whitespaces)

            let names = cleaned
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count < 60 }
            if !names.isEmpty { return names }
        }
        return nil
    }

    /// Lines the prep checklist should drop because they're event metadata
    /// the invite row already renders. Avoids double-rendering "Attendees: …"
    /// or "Meet: https://…" as toggleable checkboxes.
    static func isEventMetadataLine(_ raw: String) -> Bool {
        let s = raw
            .replacingOccurrences(of: "**", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        let prefixes = [
            "event:", "title:", "subject:",
            "when:", "time:", "starts:", "starts at",
            "attendees:", "attendee:", "invitees:", "guests:",
            "meet:", "meet link", "google meet:",
            "gmail:", "gmail thread", "from calendar",
            "calendar:", "calendar invite",
            "location:",
        ]
        for p in prefixes where s.hasPrefix(p) { return true }
        // Bare Meet URL on its own line.
        if s.hasPrefix("https://meet.google.com/") { return true }
        return false
    }

    private static func looksLikeCalendarBridge(_ s: String) -> Bool {
        let lc = s.lowercased()
        return lc.contains("gmail")
            || lc.contains("calendar")
            || lc.contains("agent briefing inbox")
            || lc.contains("notion mail")
            || lc.contains("notion calendar")
            || lc.contains("meet.google.com")
    }

    private func inviteRow(_ invite: Invite) -> some View {
        HStack(spacing: 10) {
            GmailGlyph()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("From Calendar via Gmail")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(GardenStyle.ink)
                Text(attendeeLine(invite.attendees))
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink3)
            }
            Spacer()
            if let url = invite.meetUrl {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 5) {
                        MeetGlyph()
                            .frame(width: 14, height: 14)
                        Text("Join Meet")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(GardenStyle.ink2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join Google Meet")
            } else {
                HStack(spacing: 5) {
                    MeetGlyph()
                        .frame(width: 14, height: 14)
                        .opacity(0.55)
                    Text("No Meet link")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(GardenStyle.ink3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .help("Add a https://meet.google.com/... line to the [!cue] briefing to turn this into Join Meet.")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GardenStyle.card)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius)
                .strokeBorder(GardenStyle.hair, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius))
    }

    private func attendeeLine(_ a: [String]) -> String {
        if a.isEmpty { return "Calendar + Gmail context" }
        let names = a.prefix(2).joined(separator: " & ")
        return a.count > 2
            ? "\(names) +\(a.count - 2) · \(a.count) attendees"
            : "\(names) · \(a.count) attendee\(a.count == 1 ? "" : "s")"
    }

    // MARK: - Body line with markdown italic

    private func bodyLine(_ text: String) -> some View {
        // AttributedString handles *italic* via .markdown parser.
        let attr = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        return Text(attr)
            .font(.system(size: 12.5))
            .foregroundColor(GardenStyle.ink2)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Prep checklist (local-only)

    private func checklist(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                checklistRow(item)
            }
        }
    }

    private func checklistRow(_ item: String) -> some View {
        let isChecked = checkedItems.contains(item)
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if isChecked { checkedItems.remove(item) } else { checkedItems.insert(item) }
            }
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
                    .strikethrough(isChecked, color: GardenStyle.ink4)
                    .foregroundColor(isChecked ? GardenStyle.ink3 : GardenStyle.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())  // entire row is the hit target
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Prep: \(item)")
        .accessibilityHint(isChecked ? "Checked, tap to uncheck" : "Tap to mark done")
    }

    // MARK: - Action row

    private func actionRow(_ cue: CueCard) -> some View {
        HStack(spacing: GardenStyle.actionRowGap) {
            actionPill(label: "↗ Open in Notion", kind: .primary) { openSource(cue) }
            actionPill(
                label: snoozedMinutes > 0 ? "Un-snooze" : "Snooze 5m",
                kind: .ghost
            ) {
                snoozedMinutes = snoozedMinutes > 0 ? 0 : 5
            }
            actionPill(label: "Ask Compost ↗", kind: .muted) {
                Task { await manager.openScene(.voice) }
            }
            Spacer()
        }
    }

    private enum PillKind { case primary, ghost, muted }

    private func actionPill(label: String, kind: PillKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(kind == .primary ? .white : (kind == .muted ? GardenStyle.ink3 : GardenStyle.ink))
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

    private func metaRow(_ cue: CueCard) -> some View {
        HStack {
            Spacer()
            Text("[!cue] · \(cleanSource(cue))")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
                .lineLimit(1)
        }
    }

    private func cleanSource(_ cue: CueCard) -> String {
        cue.sourceTitle
            .replacingOccurrences(of: "[!cue]", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func openSource(_ cue: CueCard) {
        let id = cue.sourcePageId.replacingOccurrences(of: "-", with: "")
        guard !id.isEmpty, let url = URL(string: "notion://www.notion.so/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Empty state

    private var emptyCue: some View {
        VStack(spacing: 10) {
            Mascot(size: 56, mood: .calm)
            Text("No cue right now.")
                .font(.callout.weight(.semibold))
                .foregroundColor(GardenStyle.ink)
            Text("The Steward publishes briefings into [!cue] Agent Briefing Inbox; the cue sync surfaces them every 5 min.")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Loads the user-provided "gmail-logo" image asset from the bundle when
/// present, falling back to a neutral geometric placeholder so the row
/// still renders if the asset is missing.
private struct GmailGlyph: View {
    var body: some View {
        if NSImage(named: "gmail-logo") != nil {
            Image("gmail-logo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.07))
            Image(systemName: "envelope")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.85))
        }
    }
}

/// Same pattern for the user-provided "meet-logo" asset.
private struct MeetGlyph: View {
    var body: some View {
        if NSImage(named: "meet-logo") != nil {
            Image("meet-logo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.10))
            Image(systemName: "video.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.85))
        }
    }
}

private struct CuePulse: ViewModifier {
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
