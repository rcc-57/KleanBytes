import AppKit
import SwiftUI

@main
struct KleanBytesApp: App {
    @State private var model = DiskScannerViewModel()

    init() {
        if let icon = NSImage(named: "KleanBytesLogo") {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("KleanBytes") {
            ContentView(model: model)
                .containerBackground(.clear, for: .window)
        }
        .defaultSize(width: 920, height: 620)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
    }
}
