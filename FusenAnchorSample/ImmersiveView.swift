//
//  ImmersiveView.swift
//  FusenAnchorSample
//
//  Created by 酒井雄太 on 2025/10/30.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {

    var body: some View {
        RealityView { content in
            
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
