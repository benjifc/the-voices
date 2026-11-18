import Foundation

public struct DeEsserSettings: Sendable {
    /// Frecuencia central de la banda de sibilancias (Hz).
    public var frequency: Float
    /// Nivel de pico de la banda (dBFS) a partir del cual se reduce.
    public var thresholdDb: Float
    /// Reducción máxima de la banda (dB). Se interpreta en valor absoluto.
    public var maxReductionDb: Float

    public init(frequency: Float, thresholdDb: Float, maxReductionDb: Float) {
        self.frequency = frequency
        self.thresholdDb = thresholdDb
        self.maxReductionDb = maxReductionDb
    }
}

/// De-esser de banda dividida y latencia cero.
///
/// `bp = bandPass(x)`; `y = x − (1 − g)·bp`, con `g` la ganancia (≤ 1) aplicada a la
/// banda según su envolvente (ratio 4, hasta `maxReductionDb`).
///
/// `update` no asigna memoria, pero no es atómico: no debe llamarse desde otro hilo
/// mientras `process` se ejecuta.
public final class DeEsser: AudioEffect {
    private static let ratioSlope: Float = 1 - 1 / 4
    private static let bandQ: Float = 1.0

    private let band: Biquad
    private var thresholdDb: Float = 0
    private var maxReduction: Float = 0
    private let detectorDecay = timeConstantCoefficient(ms: 5, sampleRate: sampleRate)
    private let attackCoef = timeConstantCoefficient(ms: 1, sampleRate: sampleRate)
    private let releaseCoef = timeConstantCoefficient(ms: 30, sampleRate: sampleRate)

    private var envelope: Float = 0
    /// Reducción actual de la banda en dB (≤ 0), suavizada.
    private var reductionDb: Float = 0

    public init(_ s: DeEsserSettings) {
        band = Biquad(.bandPass, frequency: s.frequency, q: DeEsser.bandQ)
        update(s)
    }

    public func update(_ s: DeEsserSettings) {
        band.configure(.bandPass, frequency: s.frequency, q: DeEsser.bandQ)
        thresholdDb = s.thresholdDb
        maxReduction = abs(s.maxReductionDb)
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let x = buffer[i]
            let bp = band.processSample(x)

            envelope = max(abs(bp), envelope * detectorDecay)
            if envelope < 1e-10 { envelope = 0 }

            var targetDb: Float = 0
            if envelope > 0 {
                let over = 20 * log10f(envelope) - thresholdDb
                if over > 0 { targetDb = -min(over * DeEsser.ratioSlope, maxReduction) }
            }

            let coef = targetDb < reductionDb ? attackCoef : releaseCoef
            reductionDb = targetDb + coef * (reductionDb - targetDb)
            if abs(reductionDb) < 1e-6 { reductionDb = 0 }

            let g: Float = reductionDb > -0.0001 ? 1 : dbToGain(reductionDb)
            buffer[i] = x - (1 - g) * bp
        }
    }

    public func reset() {
        band.reset()
        envelope = 0
        reductionDb = 0
    }
}
