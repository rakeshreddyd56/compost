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

            topPip

            Divider()

            ScrollView {
                content
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

    // MARK: - Top pip (success ✓, offline ⚠, or loading …)

    @ViewBuilder
    private var topPip: some View {
        if let success = manager.lastSuccess {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(GardenStyle.accentGreen)
                Text(successMessage(success))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, GardenStyle.cardPadding)
            .transition(.opacity)
            .accessibilityLabel(successMessage(success))
        } else if let actionErr = manager.lastActionError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text(actionErr)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, GardenStyle.cardPadding)
            .transition(.opacity)
            .accessibilityLabel(actionErr)
        } else if let err = manager.summary.lastError {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, GardenStyle.cardPadding)
            .accessibilityLabel("Sync issue: \(err)")
        } else if !manager.hasLoadedOnce {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking your workspace…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, GardenStyle.cardPadding)
            .accessibilityLabel("Loading workspace state")
        }
    }

    private func successMessage(_ ping: SuccessPing) -> String {
        switch ping {
        case .tidied:                     return "Tidy run kicked off"
        case .applied:                    return "Approved proposals applied"
        case .proposalApplied(let title): return "Applied: \(title)"
        case .reviewed:                   return "Draft reviewed"
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private var content: some View {
        if !manager.hasLoadedOnce {
            loadingState
        } else if !manager.summary.hasAnything && manager.summary.currentCue == nil {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: GardenStyle.sectionGap) {
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
                    // Global "Apply approved" removed in favour of per-row
                    // "Approve & apply" buttons (see ProposalRow). Each row
                    // is reviewable independently so users opt in per item.
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
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            Mascot(size: 56, mood: .calm)
            ProgressView()
                .controlSize(.small)
            Text("Compost is checking on your workspace…")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading. Compost is checking your workspace.")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Mascot(size: 64, mood: .calm)
            Text("Your workspace is calm.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
            Text("Nothing to tidy. ✨")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your workspace is calm. Nothing to tidy.")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Mascot(size: 22, mood: mascotMood)
            Text(greeting)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
            tidyButton
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

    private var tidyButton: some View {
        let busy = manager.inflight.contains(.tidyNow)
        return Button(action: { Task { await manager.tidyNow() } }) {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "wand.and.stars.inverse").font(.caption)
                }
                Text(busy ? "Tidying…" : "Tidy now").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(.white)
            .background(GardenStyle.accentGreen)
            .cornerRadius(GardenStyle.cornerRadius)
            .opacity(busy ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help("Trigger Gardener worker now")
        .accessibilityLabel(busy ? "Tidy in progress" : "Tidy now")
        .accessibilityHint("Runs the Gardener worker to refresh proposals")
    }

    // MARK: - Helpers

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

    private var mascotMood: Mascot.Mood {
        if manager.inflight.contains(.tidyNow) || manager.inflight.contains(.applyApproved) {
            return .sweep
        }
        if manager.summary.lastError != nil { return .calm }
        let imminent = (manager.summary.currentCue?.minutesUntilNext ?? 0)
        if imminent > 0 && imminent < 10 { return .alert }
        if manager.summary.hasAnything { return .nudging }
        return .calm
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
