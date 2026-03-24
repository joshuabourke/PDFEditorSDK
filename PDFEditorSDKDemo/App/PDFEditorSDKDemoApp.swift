//
//  PDFEditorSDKDemoApp.swift
//  PDFEditorSDKDemo
//
//  Created by Josh Bourke on 16/12/2025.
//

import SwiftUI

@main
struct PDFEditorSDKDemoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let sampleURL = Bundle.main.url(forResource: "SampleForm", withExtension: "pdf") {
                    PDFEditorView(url: sampleURL)
                } else {
                    ContentUnavailableView(
                        "Sample PDF Missing",
                        systemImage: "doc",
                        description: Text("Add `SampleForm.pdf` to the app bundle to preview the SDK.")
                    )
                }
            }
        }
    }
}
