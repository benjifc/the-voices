import Foundation

public struct GateSettings: Sendable {
    /// Nivel de pico (dBFS) por debajo del cual la puerta empieza a cerrarse.
    public var thresholdDb: Float
    /// Atenuación (dB, ≤ 0) con la puerta cerrada: es un expansor, no silencia del todo.
    public var rangeDb: Float
    /// Tiempo de apertura (constante de tiempo, ms).
    public var attackMs: Float
    /// Tiempo que la puerta se mantiene abierta tras caer la señal por debajo del umbral.
    public var holdMs: Float
    /// Tiempo de cierre (constante de tiempo, ms).
    public var releaseMs: Float

    public init(
        thresholdDb: Float, rangeDb: Float, attackMs: Float, holdMs: Float, releaseMs: Float
    ) {
        self.thresholdDb = thresholdDb
        self.rangeDb = rangeDb
        self.attackMs = attackMs
        self.holdMs = holdMs
        self.releaseMs = releaseMs
    }
}

/// Puerta de ruido (expansor) con detector de envolvente de pico y tiempo de retención.
///
/// El tiempo efectivo de apertura tras la última señal sobre el umbral es `holdMs` más lo
/// que tarda la envolvente de pico (decaimiento de 10 ms) en caer por debajo del umbral.
///
/// `update` no asigna memoria, pero no es atómico: no debe llamarse desde otro hilo
/// mientras `process` se ejecuta.
public final class NoiseGate: AudioEffect {
    private static let detectorReleaseMs: Float = 10

    private var thresholdLinear: Float = 0
    private var rangeDb: Float = 0
    private var attackCoef: Float = 0
    private var releaseCoef: Float = 0
    private var holdSamples = 0
    private let detectorDecay = timeConstantCoefficient(
        ms: NoiseGate.detectorReleaseMs, sampleRate: sampleRate)

    private var envelope: Float = 0
    private var holdCounter = 0
    /// Ganancia actual en dB (≤ 0), suavizada.
    private var gainDb: Float = 0

    public init(_ s: GateSettings) {
        update(s)
    }

    public func update(_ s: GateSettings) {
        thresholdLinear = dbToGain(s.thresholdDb)
        rangeDb = min(s.rangeDb, 0)
        attackCoef = timeConstantCoefficient(ms: max(s.attackMs, 0.01), sampleRate: sampleRate)
        releaseCoef = timeConstantCoefficient(ms: max(s.releaseMs, 0.01), sampleRate: sampleRate)
        holdSamples = max(Int(s.holdMs * 0.001 * Float(sampleRate)), 0)
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let x = buffer[i]
            let level = abs(x)
            envelope = max(level, envelope * detectorDecay)
            if envelope < 1e-10 { envelope = 0 }

            let targetDb: Float
            if envelope > thresholdLinear {
                holdCounter = holdSamples
                targetDb = 0
            } else if holdCounter > 0 {
                holdCounter -= 1
                targetDb = 0
            } else {
                targetDb = rangeDb
            }

            // Abrir = ganancia sube (attack); cerrar = ganancia baja (release).
            let coef = targetDb < gainDb ? releaseCoef : attackCoef
            gainDb = targetDb + coef * (gainDb - targetDb)
            if abs(gainDb) < 1e-6 { gainDb = 0 }
            let gain: Float = gainDb > -0.0001 ? 1 : dbToGain(gainDb)
            buffer[i] = x * gain
        }
    }

    public func reset() {
        envelope = 0
        holdCounter = 0
        gainDb = 0
    }
}
