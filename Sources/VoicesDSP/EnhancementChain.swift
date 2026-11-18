import Foundation

/// Intensidad de la cadena "Mi voz mejorada".
public enum EnhancementLevel: Int, CaseIterable, Sendable {
    case soft = 0
    case normal = 1
    case radio = 2

    public var displayName: String {
        switch self {
        case .soft: "Suave"
        case .normal: "Normal"
        case .radio: "Radio"
        }
    }
}

/// Valores de cada etapa para un nivel.
private struct EnhancementParameters {
    var highPassHz: Float
    var gate: GateSettings
    var lowShelfDb: Float  // 150 Hz
    var mudDb: Float  // peak 300 Hz, Q 1
    var presenceDb: Float  // peak 3 kHz, Q 1
    var highShelfDb: Float  // 10 kHz
    var compressor: CompressorSettings
    var deEsser: DeEsserSettings

    init(level: EnhancementLevel) {
        switch level {
        case .soft:
            highPassHz = 80
            gate = GateSettings(
                thresholdDb: -50, rangeDb: -10, attackMs: 1, holdMs: 150, releaseMs: 200)
            lowShelfDb = 1
            mudDb = -1
            presenceDb = 1.5
            highShelfDb = 1
            compressor = CompressorSettings(
                thresholdDb: -20, ratio: 2, attackMs: 10, releaseMs: 120, makeupDb: 2)
            deEsser = DeEsserSettings(frequency: 6500, thresholdDb: -30, maxReductionDb: 6)
        case .normal:
            highPassHz = 80
            gate = GateSettings(
                thresholdDb: -45, rangeDb: -12, attackMs: 1, holdMs: 150, releaseMs: 200)
            lowShelfDb = 2
            mudDb = -2
            presenceDb = 2.5
            highShelfDb = 2
            compressor = CompressorSettings(
                thresholdDb: -22, ratio: 3, attackMs: 8, releaseMs: 100, makeupDb: 4)
            deEsser = DeEsserSettings(frequency: 6500, thresholdDb: -30, maxReductionDb: 8)
        case .radio:
            highPassHz = 90
            gate = GateSettings(
                thresholdDb: -42, rangeDb: -15, attackMs: 1, holdMs: 150, releaseMs: 200)
            lowShelfDb = 3
            mudDb = -3
            presenceDb = 4
            highShelfDb = 3
            compressor = CompressorSettings(
                thresholdDb: -26, ratio: 4, attackMs: 5, releaseMs: 80, makeupDb: 7)
            deEsser = DeEsserSettings(frequency: 6500, thresholdDb: -32, maxReductionDb: 10)
        }
    }
}

/// Cadena de voz mejorada, sin latencia:
/// HPF → puerta → lowShelf → peak (barro) → peak (presencia) → highShelf → compresor → de-esser.
///
/// No incluye limitador (va al final de `VoiceProcessor`).
/// `setLevel` no asigna memoria y conserva el estado de cada etapa, así que puede llamarse
/// desde el hilo de audio; no es atómico entre etapas, por lo que no debe llamarse desde
/// otro hilo mientras `process` se ejecuta.
public final class EnhancementChain: AudioEffect {
    private static let highPassQ: Float = 0.707
    private static let shelfQ: Float = 0.707
    private static let lowShelfHz: Float = 150
    private static let mudHz: Float = 300
    private static let presenceHz: Float = 3000
    private static let highShelfHz: Float = 10_000
    private static let peakQ: Float = 1

    private let highPass: Biquad
    private let gate: NoiseGate
    private let lowShelf: Biquad
    private let mud: Biquad
    private let presence: Biquad
    private let highShelf: Biquad
    private let compressor: Compressor
    private let deEsser: DeEsser

    public init(level: EnhancementLevel) {
        let p = EnhancementParameters(level: level)
        highPass = Biquad(.highPass, frequency: p.highPassHz, q: Self.highPassQ)
        gate = NoiseGate(p.gate)
        lowShelf = Biquad(.lowShelf(gainDb: p.lowShelfDb), frequency: Self.lowShelfHz, q: Self.shelfQ)
        mud = Biquad(.peak(gainDb: p.mudDb), frequency: Self.mudHz, q: Self.peakQ)
        presence = Biquad(.peak(gainDb: p.presenceDb), frequency: Self.presenceHz, q: Self.peakQ)
        highShelf = Biquad(
            .highShelf(gainDb: p.highShelfDb), frequency: Self.highShelfHz, q: Self.shelfQ)
        compressor = Compressor(p.compressor)
        deEsser = DeEsser(p.deEsser)
    }

    public func setLevel(_ level: EnhancementLevel) {
        let p = EnhancementParameters(level: level)
        highPass.configure(.highPass, frequency: p.highPassHz, q: Self.highPassQ)
        gate.update(p.gate)
        lowShelf.configure(.lowShelf(gainDb: p.lowShelfDb), frequency: Self.lowShelfHz, q: Self.shelfQ)
        mud.configure(.peak(gainDb: p.mudDb), frequency: Self.mudHz, q: Self.peakQ)
        presence.configure(.peak(gainDb: p.presenceDb), frequency: Self.presenceHz, q: Self.peakQ)
        highShelf.configure(
            .highShelf(gainDb: p.highShelfDb), frequency: Self.highShelfHz, q: Self.shelfQ)
        compressor.update(p.compressor)
        deEsser.update(p.deEsser)
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        highPass.process(buffer, frameCount: frameCount)
        gate.process(buffer, frameCount: frameCount)
        lowShelf.process(buffer, frameCount: frameCount)
        mud.process(buffer, frameCount: frameCount)
        presence.process(buffer, frameCount: frameCount)
        highShelf.process(buffer, frameCount: frameCount)
        compressor.process(buffer, frameCount: frameCount)
        deEsser.process(buffer, frameCount: frameCount)
    }

    public func reset() {
        highPass.reset()
        gate.reset()
        lowShelf.reset()
        mud.reset()
        presence.reset()
        highShelf.reset()
        compressor.reset()
        deEsser.reset()
    }
}
