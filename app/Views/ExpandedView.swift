//
//  ExpandedView.swift
//  Compost — expanded notch card.
//
//  v0.5 shell: deep notchBg (#050608), translucent inner cards, pill buttons.
//

import SwiftUI

struct ExpandedView: View {
    @ObservedObject var manager: NotchManager
    @State private var appeared = false
    @State private var showingPhotos = false

    var body: some View {
        Group {
            if showingPhotos {
                PhotosView(manager: manager, isPresented: $showingPhotos)
            } else {
                summaryCard
            }
        }
        .onAppear {
            if GardenStyle.reduceMotion {
                appeared = true
            } else {
                withAnimation(GardenStyle.spring) { appeared = true }
            }
        }
    }

    // MARK: - Standard summary card

    private var summaryCard: some View {
        VStack(spacing: GardenStyle.expandedInnerGap) {
            header
            topPip
            ScrollView {
                content
                    .padding(.horizontal, GardenStyle.cardPadding)
                    .padding(.bottom, GardenStyle.cardPadding)
            }
            .frame(maxHeight: 420)
            .scrollContentBackground(.hidden)
        }
        .frame(width: GardenStyle.expandedWidth)
        .padding(.top, 14)
        .background(GardenStyle.notchBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: GardenStyle.expandedR,
                bottomTrailingRadius: GardenStyle.expandedR,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
    }

    // MARK: - Top pip

    @ViewBuilder
    private var topPip: some View {
        if let success = manager.lastSuccess {
            pip(icon: "checkmark.circle.fill", tint: GardenStyle.sage300,
                text: successMessage(success))
        } else if let actionErr = manager.lastActionError {
            pip(icon: "exclamationmark.triangle.fill", tint: GardenStyle.accentRose, text: actionErr)
        } else if let err = manager.summary.lastError {
            pip(icon: "wifi.exclamationmark", tint: GardenStyle.accentAmber, text: err, secondary: true)
        } else if !manager.hasLoadedOnce {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(GardenStyle.ink3)
                Text("Checking your workspace…")
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink3)
                Spacer()
            }
            .padding(.horizontal, GardenStyle.cardPadding)
        }
    }

    private func pip(icon: String, tint: Color, text: String, secondary: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(tint)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(secondary ? GardenStyle.ink3 : GardenStyle.ink2)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, GardenStyle.cardPadding)
        .transition(.opacity)
        .accessibilityLabel(text)
    }

    private func successMessage(_ ping: SuccessPing) -> String {
        switch ping {
        case .tidied:                       return "Tidy proposals refreshed"
        case .applied:                      return "Approved proposals applied"
        case .proposalApplied(let title):   return "Applied: \(title)"
        case .reviewed:                     return "Draft reviewed"
        case .voiceCaptured(let preview):
            let t = preview.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Voice captured" : "Voice: \(t.prefix(60))"
        case .memoryTagged(let title, let tag): return "#\(tag) → \(title)"
        case .workspaceRefreshed:           return "Workspace refreshed"
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if !manager.hasLoadedOnce {
            loadingState
        } else if !manager.summary.hasAnything && manager.summary.currentCue == nil {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: GardenStyle.sectionGap) {
                if let cue = manager.summary.currentCue {
                    sectionLabel("☀ Up next")
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
                            .foregroundColor(GardenStyle.ink3)
                    }
                }

                if manager.summary.draftCount > 0 {
                    sectionLabel("🌙 Drafts on ice")
                    ForEach(Array(manager.summary.drafts.prefix(3).enumerated()), id: \.element.id) { idx, draft in
                        DraftRow(draft: draft, manager: manager)
                            .staggered(index: idx + 6, appeared: appeared)
                    }
                }

                if manager.summary.memoryCount > 0 || hasMemoryDb {
                    MemorySection(manager: manager, showingPhotos: $showingPhotos)
                        .staggered(index: 10, appeared: appeared)
                }

                if manager.summary.digestReady, let url = manager.summary.digestUrl {
                    sectionLabel("📰 Sunday digest")
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "newspaper")
                            Text("Open this week's digest")
                                .font(.callout.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundColor(.white)
                        .background(Capsule().fill(GardenStyle.accentGreen))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open weekly digest in Notion")
                }
            }
        }
    }

    private var hasMemoryDb: Bool {
        !(Keychain.get(.notionMemoryDbId) ?? "").isEmpty
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            Mascot(size: 56, mood: .calm)
            ProgressView().controlSize(.small).tint(GardenStyle.sage300)
            Text("Compost is checking on your workspace…")
                .font(.callout)
                .foregroundColor(GardenStyle.ink2)
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
                .foregroundColor(GardenStyle.ink)
            Text("Nothing to tidy. ✨")
                .font(.caption)
                .foregroundColor(GardenStyle.ink3)
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
                .foregroundColor(GardenStyle.ink)
            Spacer()
            tidyButton
            closeButton
        }
        .padding(.horizontal, GardenStyle.cardPadding)
    }

    private var closeButton: some View {
        Button { Task { await manager.collapseToHidden() } } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundColor(GardenStyle.ink2)
                .frame(width: 24, height: 24)
                .background(Circle().fill(GardenStyle.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private var tidyButton: some View {
        let busy = manager.inflight.contains(.tidyNow)
        return Button(action: { Task { await manager.refreshAll() } }) {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                Text(busy ? "Refreshing…" : "Refresh").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundColor(.white)
            .background(Capsule().fill(GardenStyle.accentGreen))
            .opacity(busy ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help("Refresh Gardener proposals and memory bridge pages. Cue publishes through its Worker sync.")
        .accessibilityLabel(busy ? "Refreshing workspace" : "Refresh workspace")
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundColor(GardenStyle.sage300)
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
