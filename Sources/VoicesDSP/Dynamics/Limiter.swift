import Foundation

/// Limitador de pico con lookahead (línea de retardo) y techo garantizado.
///
/// En cada instante `n` se emite `x[n − L]` multiplicado por la media, sobre las últimas
/// `L + 1` muestras, de una envolvente de ganancia que nunca supera la ganancia necesaria
/// (`techo / |x[k]|`) de ninguna muestra de la ventana `[n − L, n]`; por tanto
/// `|y| ≤ techo` siempre. La envolvente baja al instante y se recupera con `releaseMs`.
/// Se reserva toda la memoria en `init`; `process` no asigna.
public final class Limiter: AudioEffect {
    /// Latencia en muestras (igual al lookahead).
    public let latencySamples: Int

    private let ceilingGain: Float
    private let releaseCoef: Float
    private let window: Int  // latencySamples + 1

    private let delay: UnsafeMutablePointer<Float>  // latencySamples
    private let requiredGains: UnsafeMutablePointer<Float>  // window
    private let envelopes: UnsafeMutablePointer<Float>  // window
    private var delayPos = 0
    private var windowPos = 0
    private var envelope: Float = 1

    public init(ceilingDb: Float = -1, lookaheadMs: Float = 1, releaseMs: Float = 50) {
        latencySamples = max(Int((lookaheadMs * 0.001 * Float(sampleRate)).rounded()), 1)
        window = latencySamples + 1
        // Margen de -0,0009 dB para que el redondeo en coma flotante nunca rebase el techo.
        ceilingGain = dbToGain(ceilingDb) * 0.9999
        releaseCoef = timeConstantCoefficient(ms: max(releaseMs, 0.01), sampleRate: sampleRate)

        delay = .allocate(capacity: latencySamples)
        requiredGains = .allocate(capacity: window)
        envelopes = .allocate(capacity: window)
        delay.initialize(repeating: 0, count: latencySamples)
        requiredGains.initialize(repeating: 1, count: window)
        envelopes.initialize(repeating: 1, count: window)
    }

    deinit {
        delay.deallocate()
        requiredGains.deallocate()
        envelopes.deallocate()
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        let invWindow = 1 / Float(window)
        for i in 0..<frameCount {
            let x = buffer[i]
            let level = abs(x)
            requiredGains[windowPos] = level > ceilingGain ? ceilingGain / level : 1

            // Mínimo de la ventana de lookahead.
            var minGain: Float = 1
            for k in 0..<window { minGain = min(minGain, requiredGains[k]) }

            // Ataque instantáneo, liberación suave; nunca por encima del mínimo.
            if minGain <= envelope {
                envelope = minGain
            } else {
                envelope = minGain + releaseCoef * (envelope - minGain)
            }
            envelopes[windowPos] = envelope

            // La media suaviza la caída de ganancia a lo largo del lookahead.
            var sum: Float = 0
            for k in 0..<window { sum += envelopes[k] }
            let gain = sum * invWindow

            let delayed = delay[delayPos]
            delay[delayPos] = x
            let y = delayed * gain
            buffer[i] = min(max(y, -ceilingGain), ceilingGain)

            windowPos += 1
            if windowPos == window { windowPos = 0 }
            delayPos += 1
            if delayPos == latencySamples { delayPos = 0 }
        }
    }

    public func reset() {
        delay.update(repeating: 0, count: latencySamples)
        requiredGains.update(repeating: 1, count: window)
        envelopes.update(repeating: 1, count: window)
        delayPos = 0
        windowPos = 0
        envelope = 1
    }
}
