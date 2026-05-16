//
//  DraftRow.swift
//  Compost — individual frozen draft row
//

import SwiftUI

struct DraftRow: View {
    let draft: FrozenDraft
    @ObservedObject var manager: NotchManager
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(draft.frozenAt)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button(action: {
                        Task { await manager.reviewDraft(draftId: draft.draftId, approve: true) }
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Accept rewrite")

                    Button(action: {
                        Task { await manager.reviewDraft(draftId: draft.draftId, approve: false) }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Reject rewrite")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Original:")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(draft.original)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text("Calmer rewrite:")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                Text(draft.rewrite)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(6)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
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
