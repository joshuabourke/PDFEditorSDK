//
//  BackgroundModifier.swift
//  VideoExamples
//
//  Created by Josh Bourke on 16/12/2025.
//

import SwiftUI

struct BackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thickMaterial)
    }
}

extension View {
    
    func backgroundModifier() -> some View {
        modifier(BackgroundModifier())
    }
    
}
