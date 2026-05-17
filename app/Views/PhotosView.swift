//
//  PhotosView.swift
//  Compost — 📷 Memory pile slideshow surface (real notionMemory photos).
//
//  Reads directly from manager.summary.memoryPhotos. No fake fixtures: if
//  the user has no photo-kind rows the surface renders an honest empty
//  state with instructions for getting one in.
//

import SwiftUI

struct PhotosView: View {
    @ObservedObject var manager: NotchManager
    @Binding var isPresented: Bool

    @State private var idx: Int = 0
    @State private var playing: Bool = true
    @State private var tagEditorOpen: Bool = false
    @State private var tagInput: String = ""
    @State private var lastTick: Date = Date()

    private var photos: [MemoryItem] { manager.summary.memoryPhotos }
    private var current: MemoryItem? {
        guard !photos.isEmpty else { return nil }
        return photos[min(idx, photos.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GardenStyle.expandedInnerGap) {
            header
            if photos.isEmpty {
                emptyState
            } else {
                viewer
                dots
                inlineError
                actions
            }
        }
        .padding(GardenStyle.cardPadding)
        .frame(width: GardenStyle.wideWidth)
        .background(GardenStyle.notchBg)
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.expandedR, style: .continuous))
        .onAppear {
            if idx >= photos.count { idx = 0 }
            lastTick = Date()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Mascot(size: 28, mood: headerMood)
            VStack(alignment: .leading, spacing: 1) {
                Text("📷 MEMORY PILE · \(photos.count) PHOTO\(photos.count == 1 ? "" : "S")")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundColor(GardenStyle.sage300)
                Text(current?.title ?? "—")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(GardenStyle.ink)
                    .lineLimit(1)
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(GardenStyle.ink3)
                    .padding(6)
                    .background(Circle().fill(GardenStyle.card))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close photos")
        }
    }

    private var headerMood: Mascot.Mood {
        guard let r = current?.mascotReaction else { return .calm }
        switch r {
        case .selfSighting: return .alert
        case .delighted:    return .nudging
        case .nostalgic:    return .calm
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Mascot(size: 64, mood: .calm)
            Text("No photos in the pile yet.")
                .font(.callout.weight(.semibold))
                .foregroundColor(GardenStyle.ink)
            Text("Drop a photo into your Notion Memory parent page. The next memoryIngest cycle (~15 min) will surface it here.")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Back") { isPresented = false }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundColor(GardenStyle.sage300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Viewer

    private var viewer: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Color.black
                if let url = current?.assetURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Text("couldn't load photo")
                                .font(.caption)
                                .foregroundColor(GardenStyle.ink3)
                        case .empty:
                            ProgressView()
                                .controlSize(.small)
                                .tint(GardenStyle.ink2)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius))
            .overlay(arrows, alignment: .center)
            .overlay(captionStrip, alignment: .bottom)
            .overlay(playPause, alignment: .topTrailing)
            .id(current?.id)
            .transition(GardenStyle.reduceMotion ? .identity : .opacity)
            .animation(.easeOut(duration: 0.22), value: idx)

            if let reaction = current?.mascotReaction {
                MascotBubble(text: bubbleCopy(for: reaction, place: current?.caption ?? ""))
                    .padding(.top, 12).padding(.leading, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        // Auto-advance ticker that respects pause + reduce-motion.
        .background(TimelineView(.periodic(from: lastTick, by: 0.5)) { ctx in
            Color.clear.onChange(of: ctx.date) { now in
                guard playing, !tagEditorOpen, !GardenStyle.reduceMotion else { return }
                let dwell: TimeInterval = current?.mascotReaction != nil ? 5.0 : 3.5
                if now.timeIntervalSince(lastTick) >= dwell {
                    advance()
                    lastTick = now
                }
            }
        })
    }

    private var captionStrip: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(current?.caption.isEmpty == false ? current!.caption : (current?.title ?? ""))
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
            if let when = current?.timeLabel(), !when.isEmpty {
                Text("🕒 \(when)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [.black.opacity(0.75), .clear],
            startPoint: .bottom, endPoint: .top
        ))
    }

    private var arrows: some View {
        HStack {
            arrow(systemName: "chevron.left", action: previous)
            Spacer()
            arrow(systemName: "chevron.right", action: advance)
        }
        .padding(.horizontal, 8)
    }

    private func arrow(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName == "chevron.left" ? "Previous photo" : "Next photo")
    }

    private var playPause: some View {
        Button { playing.toggle(); lastTick = Date() } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel(playing ? "Pause slideshow" : "Play slideshow")
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(photos.indices, id: \.self) { i in
                Button { idx = i; lastTick = Date() } label: {
                    Capsule()
                        .fill(dotColor(at: i))
                        .frame(width: i == idx ? 18 : 6, height: 6)
                        .animation(GardenStyle.springExpand, value: idx)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(i + 1) of \(photos.count)")
            }
            Spacer()
            Text("\(idx + 1) / \(photos.count)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(GardenStyle.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private func dotColor(at i: Int) -> Color {
        if i == idx { return GardenStyle.sage400 }
        if photos[i].mascotReaction != nil { return GardenStyle.accentGold.opacity(0.55) }
        return Color.white.opacity(0.20)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if tagEditorOpen {
            tagEditor
        } else {
            HStack(spacing: GardenStyle.actionRowGap) {
                actionPill(label: "↗ Open in Notion", primary: true) {
                    if let url = current?.sourceURL { NSWorkspace.shared.open(url) }
                }
                actionPill(label: "+ Tag", primary: false) {
                    withAnimation(GardenStyle.spring) { tagEditorOpen = true }
                }
                Spacer()
                if let tags = current?.tags, !tags.isEmpty {
                    tagChips(tags)
                }
            }
        }
    }

    private var tagEditor: some View {
        HStack(spacing: 6) {
            TextField("tag…", text: $tagInput, onCommit: saveTag)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundColor(GardenStyle.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(GardenStyle.card)
                .cornerRadius(GardenStyle.cornerRadius)
                .frame(maxWidth: 220)
            Button("Save", action: saveTag)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundColor(GardenStyle.sage300)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(GardenStyle.card)
                .cornerRadius(GardenStyle.cornerRadius)
                .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") {
                tagInput = ""; tagEditorOpen = false
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(GardenStyle.ink3)
            Spacer()
        }
    }

    private func saveTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let item = current else { return }
        tagInput = ""
        tagEditorOpen = false
        Task { await manager.tagMemory(item, tag: trimmed) }
    }

    private func actionPill(label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(primary ? .white : GardenStyle.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(primary ? GardenStyle.accentGreen : GardenStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(primary ? .clear : GardenStyle.hair, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func tagChips(_ tags: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(3), id: \.self) { t in
                Text("#\(t)")
                    .font(.caption2)
                    .foregroundColor(t.lowercased() == "compost-sighting" ? GardenStyle.sage300 : GardenStyle.ink3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GardenStyle.card)
                    .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private var inlineError: some View {
        if let item = current, let err = manager.memoryErrors[item.id] {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(GardenStyle.accentRose)
                Text(err)
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink2)
                    .lineLimit(2)
                Spacer()
            }
            .padding(8)
            .background(GardenStyle.accentRose.opacity(0.08))
            .cornerRadius(GardenStyle.cornerRadius)
        }
    }

    // MARK: - Helpers

    private func advance() {
        guard !photos.isEmpty else { return }
        idx = (idx + 1) % photos.count
    }
    private func previous() {
        guard !photos.isEmpty else { return }
        idx = (idx - 1 + photos.count) % photos.count
    }

    private func bubbleCopy(for reaction: MemoryReaction, place: String) -> String {
        switch reaction {
        case .selfSighting:
            return place.isEmpty
                ? "yes — that's me! logged it."
                : "yes — that's me! \(place). logged it."
        case .delighted:
            return "this one's good. tag it for the moodboard?"
        case .nostalgic:
            return "oh — this was a while back."
        }
    }
}

// MARK: - Mascot speech bubble

struct MascotBubble: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("🌱")
            Text(text)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundColor(GardenStyle.sage300)
                .lineLimit(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GardenStyle.sage900.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(GardenStyle.sage400.opacity(0.4), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .accessibilityLabel(text)
    }
}
