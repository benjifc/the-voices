import Accelerate
import Foundation

/// Detector de tono YIN sobre señal diezmada ×2 (24 kHz).
///
/// La diferencia `d(τ) = Σ (x[j] − x[j+τ])²` se calcula con `vDSP_distancesq`. El tono se
/// elige con el primer mínimo de `d'(τ)` bajo el umbral 0,15 y se refina con una parábola.
/// Se devuelve `nil` si la confianza (`1 − d'`) es < 0,85 o si el RMS de la ventana es
/// < −50 dBFS. Todos los buffers se reservan en `init`; `push` no asigna memoria.
///
/// No es seguro para hilos: `push` y la lectura de `frequency`/`confidence` deben hacerse
/// desde el mismo hilo (o sincronizarse fuera de esta clase).
public final class PitchDetector {
    /// Última frecuencia detectada (Hz), o `nil` si no hay voz.
    public private(set) var frequency: Float?
    /// Confianza de la última detección (0…1).
    public private(set) var confidence: Float = 0

    private static let threshold: Float = 0.15
    private static let minConfidence: Float = 0.85
    private static let silenceRms = dbToGain(-50)

    private let hop: Int
    private let frameLength: Int  // muestras diezmadas por ventana
    private let integration: Int  // longitud de la suma de d(τ)
    private let tauMin: Int
    private let tauMax: Int
    private let decimatedRate: Float

    private let ring: UnsafeMutablePointer<Float>  // frameLength
    private let frame: UnsafeMutablePointer<Float>  // frameLength, ordenada
    private let normalized: UnsafeMutablePointer<Float>  // d'(τ), 0…tauMax

    private var ringPos = 0
    private var filled = 0
    private var sinceAnalysis = 0
    private var parity = 0
    private var x1: Float = 0
    private var x2: Float = 0

    public init(
        minHz: Float = 70, maxHz: Float = 1000, windowSamples: Int = 2048, hopSamples: Int = 256
    ) {
        decimatedRate = Float(sampleRate) / 2
        hop = max(hopSamples, 1)
        tauMin = max(Int(decimatedRate / maxHz), 2)
        // `tauMax + 1` queda libre para poder interpolar en el último retardo.
        let wantedTauMax = Int((decimatedRate / minHz).rounded(.up)) + 1
        frameLength = max(windowSamples / 2, 2 * wantedTauMax + 2)
        tauMax = wantedTauMax
        integration = frameLength - tauMax - 1

        ring = .allocate(capacity: frameLength)
        frame = .allocate(capacity: frameLength)
        normalized = .allocate(capacity: tauMax + 2)
        ring.initialize(repeating: 0, count: frameLength)
        frame.initialize(repeating: 0, count: frameLength)
        normalized.initialize(repeating: 1, count: tauMax + 2)
    }

    deinit {
        ring.deallocate()
        frame.deallocate()
        normalized.deallocate()
    }

    public func push(_ x: UnsafePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let s = x[i]
            // Paso bajo [¼, ½, ¼] y decimación ×2.
            let filtered = 0.25 * s + 0.5 * x1 + 0.25 * x2
            x2 = x1
            x1 = s
            parity ^= 1
            if parity == 1 {
                ring[ringPos] = filtered
                ringPos += 1
                if ringPos == frameLength { ringPos = 0 }
                if filled < frameLength { filled += 1 }
            }
            sinceAnalysis += 1
            if sinceAnalysis >= hop {
                sinceAnalysis = 0
                if filled == frameLength { analyze() }
            }
        }
    }

    private func analyze() {
        // Ventana cronológica: la más antigua está en ringPos.
        let tail = frameLength - ringPos
        frame.update(from: ring + ringPos, count: tail)
        (frame + tail).update(from: ring, count: ringPos)

        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frameLength))
        guard rms >= Self.silenceRms else {
            frequency = nil
            confidence = 0
            return
        }

        // d'(τ) = d(τ) · τ / Σ_{j≤τ} d(j)
        normalized[0] = 1
        var running: Float = 0
        for tau in 1...tauMax {
            var d: Float = 0
            vDSP_distancesq(frame, 1, frame + tau, 1, &d, vDSP_Length(integration))
            running += d
            normalized[tau] = running > 0 ? d * Float(tau) / running : 1
        }

        // Primer mínimo bajo el umbral; si no lo hay, el mínimo global.
        var best = -1
        var tau = tauMin
        while tau <= tauMax {
            if normalized[tau] < Self.threshold {
                while tau + 1 <= tauMax && normalized[tau + 1] < normalized[tau] { tau += 1 }
                best = tau
                break
            }
            tau += 1
        }
        if best < 0 {
            best = tauMin
            for t in tauMin...tauMax where normalized[t] < normalized[best] { best = t }
        }

        let conf = min(max(1 - normalized[best], 0), 1)
        confidence = conf
        guard conf >= Self.minConfidence else {
            frequency = nil
            return
        }

        // Interpolación parabólica alrededor del mínimo.
        var refined = Float(best)
        if best > 1 && best < tauMax {
            let s0 = normalized[best - 1]
            let s1 = normalized[best]
            let s2 = normalized[best + 1]
            let denominator = s0 - 2 * s1 + s2
            if denominator > 1e-9 {
                refined += min(max(0.5 * (s0 - s2) / denominator, -1), 1)
            }
        }
        frequency = decimatedRate / refined
    }
}
