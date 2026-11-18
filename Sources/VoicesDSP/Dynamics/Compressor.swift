import Foundation

public struct CompressorSettings: Sendable {
    public var thresholdDb: Float
    public var ratio: Float
    public var attackMs: Float
    public var releaseMs: Float
    public var makeupDb: Float

    public init(
        thresholdDb: Float, ratio: Float, attackMs: Float, releaseMs: Float, makeupDb: Float
    ) {
        self.thresholdDb = thresholdDb
        self.ratio = ratio
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.makeupDb = makeupDb
    }
}

/// Compresor feed-forward con detector RMS (ventana ≈ 10 ms) y rodilla dura.
///
/// `update` no asigna memoria, pero no es atómico: no debe llamarse desde otro hilo
/// mientras `process` se ejecuta.
public final class Compressor: AudioEffect {
    private static let detectorWindowMs: Float = 10

    private var thresholdDb: Float = 0
    private var slope: Float = 0  // 1 - 1/ratio
    private var makeupDb: Float = 0
    private var attackCoef: Float = 0
    private var releaseCoef: Float = 0
    private let detectorCoef = timeConstantCoefficient(
        ms: Compressor.detectorWindowMs, sampleRate: sampleRate)

    private var meanSquare: Float = 0
    /// Reducción de ganancia actual en dB (≤ 0), suavizada.
    private var reductionDb: Float = 0

    public init(_ s: CompressorSettings) {
        update(s)
    }

    public func update(_ s: CompressorSettings) {
        thresholdDb = s.thresholdDb
        slope = 1 - 1 / max(s.ratio, 1)
        makeupDb = s.makeupDb
        attackCoef = timeConstantCoefficient(ms: max(s.attackMs, 0.01), sampleRate: sampleRate)
        releaseCoef = timeConstantCoefficient(ms: max(s.releaseMs, 0.01), sampleRate: sampleRate)
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let x = buffer[i]
            meanSquare = detectorCoef * meanSquare + (1 - detectorCoef) * x * x
            if meanSquare < 1e-20 { meanSquare = 0 }

            let levelDb = 10 * log10f(meanSquare + 1e-20)
            let over = levelDb - thresholdDb
            let targetDb: Float = over > 0 ? -over * slope : 0

            // Más reducción = ataque; menos reducción = liberación.
            let coef = targetDb < reductionDb ? attackCoef : releaseCoef
            reductionDb = targetDb + coef * (reductionDb - targetDb)

            let totalDb = reductionDb + makeupDb
            let gain: Float = abs(totalDb) < 0.0001 ? 1 : dbToGain(totalDb)
            buffer[i] = x * gain
        }
    }

    public func reset() {
        meanSquare = 0
        reductionDb = 0
    }
}
