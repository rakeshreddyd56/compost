//
//  DraftRow.swift
//  Compost — individual frozen draft row with side-by-side review
//

import SwiftUI

struct DraftRow: View {
    let draft: FrozenDraft
    @ObservedObject var manager: NotchManager
    @State private var isHovering = false
    @State private var showSideBySide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .accessibilityLabel("Draft: \(draft.title)")
                    if !draft.frozenAt.isEmpty {
                        Text("frozen \(prettyTime(draft.frozenAt))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSideBySide.toggle() } }) {
                    Image(systemName: showSideBySide ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Side by side")
                .accessibilityLabel(showSideBySide ? "Hide side-by-side" : "Show side-by-side")
            }

            if showSideBySide {
                HStack(alignment: .top, spacing: 8) {
                    sideColumn(title: "What you wrote", body: draft.original, tint: .secondary)
                    sideColumn(title: "Calmer rewrite", body: draft.rewrite, tint: GardenStyle.accentGreen)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(draft.rewrite)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GardenStyle.accentGreen.opacity(0.06))
                    .cornerRadius(GardenStyle.cornerRadius)
            }

            HStack(spacing: 8) {
                let busy = manager.inflight.contains(.reviewDraft(draft.id))
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

                Button(action: {
                    Task { await manager.reviewDraft(draftId: draft.id, approve: true) }
                }) {
                    HStack(spacing: 4) {
                        if busy {
                            ProgressView().controlSize(.mini).tint(.white)
                        }
                        Text("Use calmer")
                            .font(.caption.weight(.semibold))
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
                .accessibilityLabel(busy ? "Reviewing draft" : "Use the calmer rewrite")
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(isHovering ? 0.08 : 0.05))
        .cornerRadius(GardenStyle.cornerRadius)
        .onHover { hovering in
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
            } else {
                isHovering = hovering
            }
        }
    }

    private func sideColumn(title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(tint)
            Text(body.isEmpty ? "—" : body)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(tint.opacity(0.06))
        .cornerRadius(GardenStyle.cornerRadius)
    }

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
