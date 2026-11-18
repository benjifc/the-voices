import SwiftUI

@main
struct TheVoicesApp: App {
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra("The Voices", systemImage: "waveform") {
            Button("Buscar actualizaciones…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            Divider()
            Button("Salir de The Voices") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
