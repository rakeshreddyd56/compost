//
//  ExpandedView.swift
//  Compost — expanded notch card with proposals, drafts, cue
//

import SwiftUI

struct ExpandedView: View {
    @ObservedObject var manager: NotchManager
    @State private var showTidyAnimation = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Compost")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { Task { await manager.tidyNow() } }) {
                        HStack(spacing: 2) {
                            Image(systemName: "wand.and.stars.inverse")
                                .font(.caption)
                            Text("Tidy")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Run tidy now")

                    Button(action: { Task { await manager.toggle() } }) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    if manager.summary.proposalCount > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("🪴 Gardener", systemImage: "leaf.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            ForEach(manager.summary.proposals) { proposal in
                                ProposalRow(proposal: proposal, manager: manager)
                            }
                        }
                        Divider()
                    }

                    if manager.summary.draftCount > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("🌙 Frozen Drafts", systemImage: "snowflake")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            ForEach(manager.summary.drafts) { draft in
                                DraftRow(draft: draft, manager: manager)
                            }
                        }
                        Divider()
                    }

                    if manager.summary.digestReady {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("📰 Weekly", systemImage: "newspaper.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Button(action: {
                                if let url = manager.summary.digestUrl {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                Text("View digest")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 300)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    ExpandedView(manager: NotchManager.preview)
}
