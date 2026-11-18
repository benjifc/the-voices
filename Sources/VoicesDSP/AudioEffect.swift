import Foundation

/// Frecuencia de trabajo de todo el DSP (mono).
public let sampleRate: Double = 48_000

/// Efecto de audio procesado en sitio sobre un bloque mono.
public protocol AudioEffect: AnyObject {
    func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int)
    func reset()
}

extension AudioEffect {
    /// Solo para tests y utilidades fuera del hilo de audio.
    public func process(_ samples: inout [Float]) {
        let count = samples.count
        samples.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            process(base, frameCount: count)
        }
    }
}

public func dbToGain(_ db: Float) -> Float {
    powf(10, db / 20)
}

public func gainToDb(_ gain: Float) -> Float {
    max(20 * log10f(max(gain, 0)), -120)
}

public func timeConstantCoefficient(ms: Float, sampleRate: Double) -> Float {
    expf(-1 / (ms * 0.001 * Float(sampleRate)))
}
