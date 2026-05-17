//
//  PhotosScene.swift
//  Compost — focused 📷 Photos surface. Thin wrapper around the existing
//  PhotosView so the dock can navigate to it directly.
//

import SwiftUI

struct PhotosScene: View {
    @ObservedObject var manager: NotchManager
    @State private var visible: Bool = true

    var body: some View {
        PhotosView(manager: manager, isPresented: Binding(
            get: { visible },
            set: { newVal in
                visible = newVal
                if !newVal {
                    Task { await manager.collapseToHidden() }
                }
            }
        ))
        .onAppear { visible = true }
    }
}
