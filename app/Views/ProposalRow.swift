//
//  ProposalRow.swift
//  Compost — individual proposal row
//

import SwiftUI

struct ProposalRow: View {
    let proposal: Proposal
    @ObservedObject var manager: NotchManager
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            let notionId = proposal.targetPageId.replacingOccurrences(of: "-", with: "")
            if let url = URL(string: "notion://www.notion.so/\(notionId)") {
                NSWorkspace.shared.open(url)
            }
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proposal.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(proposal.action.uppercased())
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .opacity(isHovering ? 1 : 0.5)
                }

                if !proposal.reason.isEmpty {
                    Text(proposal.reason)
                        .font(.system(.caption2, design: .default))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .buttonStyle(.plain)
        .help("Open in Notion")
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
