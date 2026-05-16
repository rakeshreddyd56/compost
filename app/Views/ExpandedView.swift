//
//  ExpandedView.swift
//  Compost — expanded notch card: ☀️ cue, 🪴 proposals, 🌙 drafts, 📰 weekly
//

import SwiftUI

struct ExpandedView: View {
    @ObservedObject var manager: NotchManager
    @State private var appeared = false

    var body: some View {
        VStack(spacing: GardenStyle.sectionGap) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: GardenStyle.sectionGap) {
                    if !manager.summary.hasAnything && manager.summary.currentCue == nil {
                        emptyState
                    } else {
                        if let cue = manager.summary.currentCue {
                            sectionLabel("☀️ Up next")
                            CueRow(cue: cue, manager: manager)
                                .staggered(index: 0, appeared: appeared)
                        }

                        if manager.summary.proposalCount > 0 {
                            sectionLabel("🪴 Tidy")
                            ForEach(Array(manager.summary.proposals.prefix(5).enumerated()), id: \.element.id) { idx, proposal in
                                ProposalRow(proposal: proposal, manager: manager)
                                    .staggered(index: idx + 1, appeared: appeared)
                            }
                            if manager.summary.proposalCount > 5 {
                                Text("+ \(manager.summary.proposalCount - 5) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button(action: { Task { await manager.applyApproved() } }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill").font(.caption)
                                    Text("Apply approved").font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundColor(.white)
                                .background(GardenStyle.accentGreen)
                                .cornerRadius(GardenStyle.cornerRadius)
                            }
                            .buttonStyle(.plain)
                            .help("Apply rows marked Approved in Notion")
                            .accessibilityLabel("Apply approved proposals")
                        }

                        if manager.summary.draftCount > 0 {
                            sectionLabel("🌙 Drafts on ice")
                            ForEach(Array(manager.summary.drafts.prefix(3).enumerated()), id: \.element.id) { idx, draft in
                                DraftRow(draft: draft, manager: manager)
                                    .staggered(index: idx + 6, appeared: appeared)
                            }
                        }

                        if manager.summary.digestReady, let url = manager.summary.digestUrl {
                            sectionLabel("📰 Sunday digest")
                            Button(action: { NSWorkspace.shared.open(url) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "newspaper")
                                    Text("Open this week's digest")
                                        .font(.callout)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(GardenStyle.accentGreen)
                                .overlay(RoundedRectangle(cornerRadius: GardenStyle.cornerRadius).stroke(GardenStyle.accentGreen, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open weekly digest in Notion")
                        }
                    }
                }
                .padding(.horizontal, GardenStyle.cardPadding)
                .padding(.bottom, GardenStyle.cardPadding)
            }
            .frame(maxHeight: 360)
        }
        .frame(width: GardenStyle.expandedWidth)
        .padding(.top, GardenStyle.cardPadding)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onAppear {
            if GardenStyle.reduceMotion {
                appeared = true
            } else {
                withAnimation(GardenStyle.spring) { appeared = true }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(greeting)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
            Button(action: { Task { await manager.tidyNow() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars.inverse").font(.caption)
                    Text("Tidy now").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(.white)
                .background(GardenStyle.accentGreen)
                .cornerRadius(GardenStyle.cornerRadius)
            }
            .buttonStyle(.plain)
            .help("Trigger Gardener worker now")
            .accessibilityLabel("Tidy now")

            Button(action: { Task { await manager.toggle() } }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, GardenStyle.cardPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 28))
                .foregroundColor(GardenStyle.accentGreen.opacity(0.7))
            Text("Your workspace is calm.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
            Text("✨")
                .font(.title3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your workspace is calm. Nothing pending.")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hello"
        }
    }
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .animation(
                GardenStyle.reduceMotion
                    ? .linear(duration: 0)
                    : .spring(response: 0.4, dampingFraction: 0.85).delay(Double(index) * 0.04),
                value: appeared
            )
    }
}

private extension View {
    func staggered(index: Int, appeared: Bool) -> some View {
        modifier(StaggeredAppear(index: index, appeared: appeared))
    }
}

#Preview {
    ExpandedView(manager: NotchManager.preview)
}
