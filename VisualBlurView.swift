//
//  VisualBlurView.swift
//  Launchpad
//
//  Created by elise123 on 2025-09-19.
//

import SwiftUI

struct VisualBlurView: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .background(Color.gray.opacity(0.1))
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

#Preview {
    VisualBlurView()
}
