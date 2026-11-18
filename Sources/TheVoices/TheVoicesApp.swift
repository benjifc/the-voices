import SwiftUI

@main
struct TheVoicesApp: App {
    var body: some Scene {
        MenuBarExtra("The Voices", systemImage: "waveform") {
            Button("Salir de The Voices") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
