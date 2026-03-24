//
//  TextFieldHeaderTextModifier.swift
//  VideoExamples
//
//  Created by Josh Bourke on 19/12/2025.
//

import SwiftUI

struct TextFieldHeaderTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}

extension View {
    
    func textFieldHeaderTextStyle() -> some View {
        modifier(TextFieldHeaderTextModifier())
    }
    
}
