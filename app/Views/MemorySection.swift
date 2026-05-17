//
//  MemorySection.swift
//  Compost — 🧠 Memory collapsible section in the expanded notch.
//
//  Renders the latest memory items pulled from the `notionMemory` managed DB.
//  Photo items show as small thumbnails (AsyncImage); notes show as text
//  cards. Tapping any row opens the source Notion page.
//

import SwiftUI

struct MemorySection: View {
    @ObservedObject var manager: NotchManager
    @AppStorage("compost.section.memory.collapsed") private var collapsed: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if !collapsed {
                if manager.summary.memory.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        .animation(GardenStyle.spring, value: collapsed)
    }

    private var headerRow: some View {
        Button(action: { collapsed.toggle() }) {
            HStack(spacing: 4) {
                Label("🧠 Memory", systemImage: "brain.head.profile")
                    .labelStyle(.titleOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                if !manager.summary.memory.isEmpty {
                    Text("· \(manager.summary.memory.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Show memory section" : "Hide memory section")
    }

    private var emptyState: some View {
        Text("Drop a photo or note in a Notion page titled with [!memory] to fill this in.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(GardenStyle.cornerRadius)
    }

    private var grid: some View {
        // Two-column lazy grid keeps thumbnails compact for the 380pt notch.
        // We render notes as text cards in the same grid so the visual rhythm
        // stays consistent.
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(manager.summary.memory.prefix(8)) { item in
                MemoryCell(item: item)
            }
        }
    }
}

private struct MemoryCell: View {
    let item: MemoryItem

    var body: some View {
        Button(action: openSource) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(GardenStyle.cornerRadius)
        }
        .buttonStyle(.plain)
        .help(item.caption.isEmpty ? item.title : item.caption)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        if item.hasPhoto, let url = URL(string: item.content) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.opacity(0.15)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.gray.opacity(0.15)
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    @unknown default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(height: 88)
                .clipped()
                if !item.caption.isEmpty {
                    Text(item.caption)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .padding(6)
                        .background(LinearGradient(
                            colors: [.black.opacity(0.0), .black.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom
                        ))
                }
            }
            .cornerRadius(GardenStyle.cornerRadius)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text(item.caption.isEmpty ? item.content : item.caption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        }
    }

    private func openSource() {
        guard let url = item.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var accessibilityText: String {
        let body = item.caption.isEmpty ? item.content : item.caption
        return "\(item.title). \(body)"
    }
}
