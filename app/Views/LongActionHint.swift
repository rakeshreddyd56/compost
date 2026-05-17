//
//  LongActionHint.swift
//  Compost — small italic hint that appears when a worker action takes
//  noticeably longer than expected. Times come from
//  `NotchManager.inflightStartedAt`.
//
//  Thresholds:
//    > 5s  → "Still working in Notion…"
//    > 15s → "Notion is taking longer than usual."
//
//  Final success/error UI still comes from the Worker response — this is
//  reassurance text only.
//

import SwiftUI

struct LongActionHint: View {
    let start: Date?

    var body: some View {
        if let start {
            TimelineView(.periodic(from: start, by: 1.0)) { context in
                let elapsed = context.date.timeIntervalSince(start)
                if elapsed > 15 {
                    hint("Notion is taking longer than usual.")
                } else if elapsed > 5 {
                    hint("Still working in Notion…")
                } else {
                    EmptyView()
                }
            }
        } else {
            EmptyView()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2.italic())
            .foregroundColor(.secondary)
            .accessibilityLabel(text)
    }
}
