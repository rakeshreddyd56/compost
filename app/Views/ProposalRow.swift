//
//  ProposalRow.swift
//  Compost — 🪴 Gardener proposal row, dark notch surface.
//

import SwiftUI

struct ProposalRow: View {
    let proposal: Proposal
    @ObservedObject var manager: NotchManager
    @State private var isHovering = false
    @State private var isExpanded = false

    private var busy: Bool {
        manager.inflight.contains(.applyProposal(proposal.proposalId))
    }
    private var inlineError: String? {
        manager.proposalErrors[proposal.proposalId]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if isExpanded { expandedDetails }
            if let err = inlineError { errorBanner(err) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? GardenStyle.cardHi : GardenStyle.card)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius)
                .strokeBorder(inlineError != nil ? GardenStyle.accentRose.opacity(0.5) : GardenStyle.hair, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius))
        .onHover { isHovering = $0 }
        .animation(GardenStyle.spring, value: isExpanded)
        .animation(GardenStyle.spring, value: inlineError)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            actionGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(GardenStyle.ink)
                    .lineLimit(1)
                if !proposal.reason.isEmpty {
                    Text(proposal.reason)
                        .font(.caption)
                        .foregroundColor(GardenStyle.ink3)
                        .lineLimit(isExpanded ? nil : 2)
                }
            }
            Spacer(minLength: 6)
            disclosureChevron
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(GardenStyle.spring) { isExpanded.toggle() } }
        .accessibilityLabel("\(proposal.action.capitalized): \(proposal.title)")
        .accessibilityHint(isExpanded ? "Collapse details" : "Expand to see details")
    }

    private var disclosureChevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundColor(GardenStyle.ink3)
    }

    // MARK: - Expanded body — only render rows that actually have data

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !proposal.action.isEmpty {
                detailRow(label: "Action", value: proposal.action.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if !proposal.reason.isEmpty {
                detailRow(label: "Reason", value: proposal.reason, multiline: true)
            }
            if !proposal.targetPageId.isEmpty {
                notionLinkRow
            }
            if !proposal.proposalId.isEmpty {
                detailRow(label: "ID", value: proposal.proposalId, mono: true)
            }
            HStack(spacing: 8) {
                approveApplyButton
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
        .padding(.leading, 28)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detailRow(label: String, value: String, mono: Bool = false, multiline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(GardenStyle.ink3)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(mono ? .system(.caption2, design: .monospaced) : .caption)
                .foregroundColor(GardenStyle.ink2)
                .lineLimit(multiline ? nil : 1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notionLinkRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Target")
                .font(.caption2.weight(.semibold))
                .foregroundColor(GardenStyle.ink3)
                .frame(width: 60, alignment: .leading)
            Button(action: openInNotion) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                    Text("Open in Notion")
                        .font(.caption)
                        .underline()
                }
                .foregroundColor(GardenStyle.sage300)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open target page in Notion")
            Spacer()
        }
    }

    private var approveApplyButton: some View {
        Button(action: {
            Task { await manager.applyProposal(proposal) }
        }) {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                }
                Text(busy ? "Applying…" : "Approve & apply")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundColor(.white)
            .background(Capsule().fill(GardenStyle.accentGreen))
            .opacity(busy ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy || proposal.proposalId.isEmpty)
        .help(proposal.proposalId.isEmpty
              ? "Missing Proposal ID — worker can't address this row"
              : "Approve this proposal and run the action immediately")
        .accessibilityLabel(busy ? "Applying proposal" : "Approve and apply proposal")
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(GardenStyle.accentRose)
                .padding(.top, 1)
            Text(err)
                .font(.caption2)
                .foregroundColor(GardenStyle.ink2)
                .lineLimit(3)
            Spacer()
        }
        .padding(8)
        .background(GardenStyle.accentRose.opacity(0.10))
        .cornerRadius(GardenStyle.cornerRadius)
        .accessibilityLabel("Apply failed: \(err)")
    }

    // MARK: - Glyph + Notion deep-link

    private var actionGlyph: some View {
        let (system, tint): (String, Color) = {
            switch proposal.action.lowercased() {
            case "archive":      return ("archivebox", GardenStyle.accentAmber)
            case "merge":        return ("arrow.triangle.merge", GardenStyle.sage400)
            case "fix_link":     return ("link", GardenStyle.sage300)
            case "add_tag":      return ("tag", GardenStyle.accentRose)
            case "delete_stub":  return ("trash", GardenStyle.accentRose)
            default:             return ("leaf", GardenStyle.sage400)
            }
        }()
        return Image(systemName: system)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 18)
            .padding(.top, 2)
    }

    private func openInNotion() {
        let notionId = proposal.targetPageId.replacingOccurrences(of: "-", with: "")
        guard !notionId.isEmpty, let url = URL(string: "notion://www.notion.so/\(notionId)") else { return }
        NSWorkspace.shared.open(url)
    }
}
