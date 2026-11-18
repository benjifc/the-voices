import Foundation

/// Cambio de tono granular con línea de retardo.
///
/// Dos lecturas de un buffer circular, desfasadas media ventana, avanzan a velocidad
/// `ratio` (retardo variable con interpolación lineal) y se mezclan con ventanas de Hann
/// complementarias (suman 1). Cambia tono y formantes a la vez.
///
/// - Con `ratio == 1` el retardo queda fijo en `latencySamples` y la salida es la entrada
///   retrasada sin alteración.
/// - Con `ratio ≠ 1` el retardo recorre toda la ventana: la latencia media es
///   `latencySamples` (ventana/2). El primer sonido tras un silencio llega, medido, en
///   ≈ 600 muestras como mucho para `ratio > 1` y ≈ 850 para `ratio < 1` (ventana 1536).
/// - `ratio` puede cambiarse entre cualquier par de muestras (`processSample`).
///
/// Todo el estado se reserva en `init`; `process` no asigna memoria.
public final class PitchShifter: AudioEffect {
    public static let minRatio: Float = 0.5
    public static let maxRatio: Float = 2.0

    /// Factor de tono (0,5…2,0); se limita a ese rango al procesar.
    public var ratio: Float = 1

    /// Latencia nominal en muestras: ventana/2.
    public let latencySamples: Int

    private let window: Int
    private let mask: Int
    private let history: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    /// Retardo de la primera lectura, en [0, window). La segunda va media ventana por detrás.
    private var delay: Double

    public init(windowSamples: Int = 1536) {
        // Par, para que las dos lecturas queden exactamente a media ventana.
        window = (max(windowSamples, 64) + 1) & ~1
        latencySamples = window / 2
        var size = 1
        while size < window + 4 { size <<= 1 }
        mask = size - 1
        history = .allocate(capacity: size)
        history.initialize(repeating: 0, count: size)
        // Empieza con la primera lectura en ventana completa (peso 1) y la segunda en peso 0.
        delay = Double(window / 2)
    }

    deinit {
        history.deallocate()
    }

    public func setSemitones(_ s: Float) {
        ratio = powf(2, s / 12)
    }

    @inline(__always)
    public func processSample(_ x: Float) -> Float {
        history[writeIndex & mask] = x

        let w = Double(window)
        let first = delay
        var second = first + w * 0.5
        if second >= w { second -= w }

        // Hann: w1 + w2 = 1 porque las lecturas están desfasadas media ventana.
        let gain1 = Float(0.5 - 0.5 * cos(2 * Double.pi * first / w))
        let y = gain1 * read(first) + (1 - gain1) * read(second)

        // Lectura a velocidad `ratio`: el retardo cambia en (1 − ratio) por muestra.
        // Un NaN haría `delay` NaN y `Int(delay)` abortaría en el hilo de audio.
        let r = ratio.isNaN ? 1.0 : Double(min(max(ratio, Self.minRatio), Self.maxRatio))
        delay += 1 - r
        if delay < 0 { delay += w } else if delay >= w { delay -= w }

        writeIndex &+= 1
        return y
    }

    /// Muestra a `delay` muestras por detrás de la última escrita (interpolación lineal).
    @inline(__always)
    private func read(_ delay: Double) -> Float {
        let whole = Int(delay)
        let frac = Float(delay - Double(whole))
        let a = history[(writeIndex - whole) & mask]
        let b = history[(writeIndex - whole - 1) & mask]
        return a + (b - a) * frac
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            buffer[i] = processSample(buffer[i])
        }
    }

    public func reset() {
        history.update(repeating: 0, count: mask + 1)
        writeIndex = 0
        delay = Double(window / 2)
    }
}
