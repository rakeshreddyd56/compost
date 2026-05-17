//
//  MemorySection.swift
//  Compost — 🧠 Memory section in ExpandedView.
//
//  Two responsibilities:
//   1. Render a quick grid of recent memory items (photo thumbnails + note
//      cards) so the user can see "yesterday's pile" at a glance.
//   2. Surface a "Open slideshow" affordance that swaps the surface into
//      PhotosView when there is at least one photo to show.
//

import SwiftUI

struct MemorySection: View {
    @ObservedObject var manager: NotchManager
    @Binding var showingPhotos: Bool
    @AppStorage("compost.section.memory.collapsed") private var collapsed = false

    private var items: [MemoryItem] { Array(manager.summary.memory.prefix(6)) }
    private var hasPhotos: Bool { !manager.summary.memoryPhotos.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !collapsed {
                if items.isEmpty {
                    emptyState
                } else {
                    grid
                    if hasPhotos {
                        Button { showingPhotos = true } label: {
                            Label("Open photos slideshow", systemImage: "photo.on.rectangle.angled")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(GardenStyle.sage300)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var header: some View {
        Button { withAnimation(GardenStyle.spring) { collapsed.toggle() } } label: {
            HStack(spacing: 6) {
                Text("🧠 Memory")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(GardenStyle.ink2)
                Text("· \(manager.summary.memoryCount)")
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink3)
                Spacer()
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundColor(GardenStyle.ink3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Expand Memory section" : "Collapse Memory section")
    }

    private var emptyState: some View {
        Text("Nothing in the pile yet. Drop a photo or note into Notion under your Memory parent page.")
            .font(.caption2)
            .foregroundColor(GardenStyle.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(GardenStyle.card)
            .cornerRadius(GardenStyle.cornerRadius)
            .accessibilityLabel("Memory pile empty")
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                MemoryCell(item: item)
            }
        }
    }
}

private struct MemoryCell: View {
    let item: MemoryItem

    var body: some View {
        Group {
            if let url = item.assetURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder(label: "couldn't load")
                    case .empty:
                        placeholder(label: "loading…")
                    @unknown default:
                        placeholder(label: "")
                    }
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(captionStrip, alignment: .bottom)
            } else {
                noteCard
            }
        }
        .background(GardenStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: GardenStyle.cornerRadius)
                .strokeBorder(GardenStyle.hair, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .accessibilityLabel(accessibilityLabel)
    }

    private var captionStrip: some View {
        Text(item.caption.isEmpty ? item.title : item.caption)
            .font(.caption2.weight(.medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(
                colors: [.black.opacity(0.65), .clear],
                startPoint: .bottom, endPoint: .top
            ))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: item.kind == .clip ? "link" : "note.text")
                    .font(.caption2)
                    .foregroundColor(GardenStyle.sage300)
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(GardenStyle.ink2)
                    .lineLimit(1)
            }
            Text(item.content.isEmpty ? item.caption : item.content)
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 90)
    }

    private func placeholder(label: String) -> some View {
        ZStack {
            Color.black.opacity(0.35)
            if !label.isEmpty {
                Text(label).font(.caption2).foregroundColor(GardenStyle.ink3)
            }
        }
        .frame(height: 90)
        .frame(maxWidth: .infinity)
    }

    private var accessibilityLabel: String {
        let kindLabel = item.kind == .photo ? "Photo" : (item.kind == .clip ? "Clip" : "Note")
        let when = item.timeLabel()
        return "\(kindLabel): \(item.caption.isEmpty ? item.title : item.caption)\(when.isEmpty ? "" : ", \(when)")"
    }

    private func open() {
        guard let url = item.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }
}
