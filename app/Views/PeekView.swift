//
//  PeekView.swift
//  Compost — collapsed notch badge
//

import SwiftUI

struct PeekView: View {
    let badge: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundColor(.green)
            Text("\(badge)")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

#Preview {
    PeekView(badge: 3)
}
