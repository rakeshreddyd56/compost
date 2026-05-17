//
//  ProposalRow.swift
//  Compost — Gardener proposal row with per-row expand + Approve & apply
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
        .background(Color.gray.opacity(isHovering ? 0.10 : 0.06))
        .cornerRadius(GardenStyle.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cornerRadius)
                .stroke(inlineError != nil ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in isHovering = hovering }
        .animation(GardenStyle.spring, value: isExpanded)
        .animation(GardenStyle.spring, value: inlineError)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header (always visible)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            actionGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !proposal.reason.isEmpty {
                    Text(proposal.reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .foregroundColor(.secondary.opacity(isHovering ? 1 : 0.6))
    }

    // MARK: - Expanded body

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(label: "Action",       value: proposal.action.replacingOccurrences(of: "_", with: " ").capitalized)
            detailRow(label: "Reason",       value: proposal.reason.isEmpty ? "—" : proposal.reason, multiline: true)
            if !proposal.targetPageId.isEmpty { notionLinkRow }
            detailRow(label: "Proposal ID",  value: proposal.proposalId.isEmpty ? "—" : proposal.proposalId, mono: true)

            HStack(spacing: 8) {
                approveApplyButton
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
        .padding(.leading, 28)  // align with title (past the glyph)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detailRow(label: String, value: String, mono: Bool = false, multiline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(mono ? .system(.caption2, design: .monospaced) : .caption)
                .foregroundColor(.primary)
                .lineLimit(multiline ? nil : 1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notionLinkRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Target")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Button(action: openInNotion) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                    Text("Open in Notion")
                        .font(.caption)
                        .underline()
                }
                .foregroundColor(GardenStyle.accentGreen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open target page in Notion")
            Spacer()
        }
    }

    private var approveApplyButton: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(.white)
                .background(GardenStyle.accentGreen)
                .cornerRadius(GardenStyle.cornerRadius)
                .opacity(busy ? 0.85 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(busy || proposal.proposalId.isEmpty)
            .help(proposal.proposalId.isEmpty
                  ? "Missing Proposal ID — worker can't address this row"
                  : "Approve this proposal and run the action immediately")
            .accessibilityLabel(busy ? "Applying proposal" : "Approve and apply proposal")

            if busy {
                LongActionHint(start: manager.inflightStartedAt[.applyProposal(proposal.proposalId)])
            }
        }
    }

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
        .accessibilityLabel("Apply failed: \(err)")
    }

    // MARK: - Glyph + Notion deep-link

    private var actionGlyph: some View {
        let (system, tint): (String, Color) = {
            switch proposal.action.lowercased() {
            case "archive":      return ("archivebox", .orange)
            case "merge":        return ("arrow.triangle.merge", .blue)
            case "fix_link":     return ("link", .purple)
            case "add_tag":      return ("tag", .pink)
            case "delete_stub":  return ("trash", .red)
            default:             return ("leaf", GardenStyle.accentGreen)
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

struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { pressed in isPressed = pressed }
    }
}

#Preview {
    let mockPage = NotionPage(
        id: "123",
        properties: [:],
        last_edited_time: nil,
        archived: false
    )
    return ProposalRow(
        proposal: Proposal(mockPage)!,
        manager: NotchManager.preview
    )
}
