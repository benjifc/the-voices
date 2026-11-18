import Combine
import Foundation
import Sparkle

/// Actualizaciones automáticas con Sparkle.
///
/// Sparkle consulta el appcast (`SUFeedURL` en `Info.plist`, el `appcast.xml` de la última
/// release de GitHub), descarga la actualización en segundo plano, comprueba su firma
/// EdDSA (`SUPublicEDKey`) y la instala. Para no cortar la voz en mitad de una llamada, la
/// instalación inmediata solo se hace cuando `isSafeToRestart()` devuelve `true`; si no,
/// se reintenta cada 5 minutos y, en cualquier caso, Sparkle instala al salir de la app.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// Se puede cambiar el criterio cuando exista el motor de audio (p. ej. «sin señal en
    /// la entrada durante 30 s»). Por defecto siempre es seguro.
    var isSafeToRestart: () -> Bool = { true }

    @Published private(set) var canCheckForUpdates = false

    private static let retryDelay: Duration = .seconds(300)

    private var controller: SPUStandardUpdaterController!
    private var observation: AnyCancellable?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
        // Sparkle espera un intervalo completo antes de la primera comprobación programada;
        // además se mira al arrancar (en segundo plano, sin interrumpir al usuario).
        controller.updater.checkForUpdatesInBackground()
    }

    /// Comprobación manual («Buscar actualizaciones…»).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    /// La actualización ya está descargada. Si es seguro, se instala y reinicia ya; si no,
    /// se espera sin perder la instalación al salir.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let install = UncheckedSendable(immediateInstallHandler)
        Task { @MainActor [weak self] in
            while let self, !self.isSafeToRestart() {
                try? await Task.sleep(for: Self.retryDelay)
            }
            install.value()
        }
        return true
    }
}

/// El bloque de Sparkle es seguro de llamar desde el hilo principal; se declara así para
/// cruzar el límite de concurrencia de Swift 6.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
