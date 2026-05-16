//
//  ProposalRow.swift
//  Compost — individual proposal row (Gardener)
//

import SwiftUI

struct ProposalRow: View {
    let proposal: Proposal
    @ObservedObject var manager: NotchManager
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: openInNotion) {
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
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(GardenStyle.accentGreen.opacity(isHovering ? 1 : 0.5))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(isHovering ? 0.12 : 0.06))
            .cornerRadius(GardenStyle.cornerRadius)
            .scaleEffect(isPressed && !GardenStyle.reduceMotion ? 0.98 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(GardenStyle.spring, value: isPressed)
            .animation(GardenStyle.spring, value: isHovering)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
        .help("Open in Notion")
        .onHover { hovering in isHovering = hovering }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(proposal.action.capitalized): \(proposal.title)")
        .accessibilityHint(proposal.reason.isEmpty ? "Opens in Notion" : "\(proposal.reason). Opens in Notion")
    }

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
