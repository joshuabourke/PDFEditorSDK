//
//  ContentBackgroundModifier.swift
//  VideoExamples
//
//  Created by Josh Bourke on 6/1/2026.
//

import SwiftUI

struct ContentBackgroundModifier: ViewModifier {
    let padding: CGFloat?
    let frameWidth: CGFloat?
    let frameHeight: CGFloat?
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(.all, padding)
            .frame(height: frameHeight)
            .frame(maxWidth: frameWidth)
            .background(Color(UIColor.tertiarySystemBackground), in: .rect(cornerRadius: cornerRadius))
    }
    

}


extension View {
    //This is going to allow me to add this custom modifier to other view I have created. This is defaulting padding to 8 but can be changed if needed.
    func contentBackgroundModifier(
        padding: CGFloat? = 8,
        frameWidth: CGFloat? = .infinity,
        frameHeight: CGFloat? = nil,
        cornerRadius: CGFloat = 12.0
    ) -> some View {
        modifier(
            ContentBackgroundModifier(
                padding: padding,
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                cornerRadius: cornerRadius
            )
        )
    }
}
