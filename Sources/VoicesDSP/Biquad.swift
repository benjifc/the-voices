import Foundation

/// Tipo de respuesta de un filtro biquad (RBJ Audio EQ Cookbook).
public enum BiquadKind: Sendable {
    case lowPass
    case highPass
    case bandPass
    case peak(gainDb: Float)
    case lowShelf(gainDb: Float)
    case highShelf(gainDb: Float)
}

/// Filtro biquad en forma directa transpuesta II.
///
/// `configure` no asigna memoria y conserva el estado, así que puede llamarse
/// desde el hilo de audio. No es atómico: no debe llamarse desde otro hilo mientras
/// `process` se ejecuta.
public final class Biquad: AudioEffect {
    // Coeficientes normalizados (a0 = 1).
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    // Estado de la forma directa transpuesta II.
    private var z1 = 0.0
    private var z2 = 0.0

    public init(_ kind: BiquadKind, frequency: Float, q: Float) {
        configure(kind, frequency: frequency, q: q)
    }

    public func configure(_ kind: BiquadKind, frequency: Float, q: Float) {
        // Mantiene la frecuencia dentro de (0, Nyquist) y la Q en un rango estable.
        let f = min(max(Double(frequency), 1), sampleRate * 0.49)
        let qd = max(Double(q), 0.05)
        let w0 = 2 * Double.pi * f / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2 * qd)

        var nb0 = 1.0, nb1 = 0.0, nb2 = 0.0
        var na0 = 1.0, na1 = 0.0, na2 = 0.0

        switch kind {
        case .lowPass:
            nb0 = (1 - cosW0) / 2
            nb1 = 1 - cosW0
            nb2 = (1 - cosW0) / 2
            na0 = 1 + alpha
            na1 = -2 * cosW0
            na2 = 1 - alpha
        case .highPass:
            nb0 = (1 + cosW0) / 2
            nb1 = -(1 + cosW0)
            nb2 = (1 + cosW0) / 2
            na0 = 1 + alpha
            na1 = -2 * cosW0
            na2 = 1 - alpha
        case .bandPass:
            // Ganancia de pico constante (0 dB en el centro).
            nb0 = alpha
            nb1 = 0
            nb2 = -alpha
            na0 = 1 + alpha
            na1 = -2 * cosW0
            na2 = 1 - alpha
        case .peak(let gainDb):
            let a = pow(10, Double(gainDb) / 40)
            nb0 = 1 + alpha * a
            nb1 = -2 * cosW0
            nb2 = 1 - alpha * a
            na0 = 1 + alpha / a
            na1 = -2 * cosW0
            na2 = 1 - alpha / a
        case .lowShelf(let gainDb):
            let a = pow(10, Double(gainDb) / 40)
            let t = 2 * a.squareRoot() * alpha
            nb0 = a * ((a + 1) - (a - 1) * cosW0 + t)
            nb1 = 2 * a * ((a - 1) - (a + 1) * cosW0)
            nb2 = a * ((a + 1) - (a - 1) * cosW0 - t)
            na0 = (a + 1) + (a - 1) * cosW0 + t
            na1 = -2 * ((a - 1) + (a + 1) * cosW0)
            na2 = (a + 1) + (a - 1) * cosW0 - t
        case .highShelf(let gainDb):
            let a = pow(10, Double(gainDb) / 40)
            let t = 2 * a.squareRoot() * alpha
            nb0 = a * ((a + 1) + (a - 1) * cosW0 + t)
            nb1 = -2 * a * ((a - 1) + (a + 1) * cosW0)
            nb2 = a * ((a + 1) + (a - 1) * cosW0 - t)
            na0 = (a + 1) - (a - 1) * cosW0 + t
            na1 = 2 * ((a - 1) - (a + 1) * cosW0)
            na2 = (a + 1) - (a - 1) * cosW0 - t
        }

        let inv = 1 / na0
        b0 = nb0 * inv
        b1 = nb1 * inv
        b2 = nb2 * inv
        a1 = na1 * inv
        a2 = na2 * inv
    }

    @inline(__always)
    public func processSample(_ x: Float) -> Float {
        let xd = Double(x)
        let y = b0 * xd + z1
        z1 = b1 * xd - a1 * y + z2
        z2 = b2 * xd - a2 * y
        return Float(y)
    }

    public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            buffer[i] = processSample(buffer[i])
        }
    }

    public func reset() {
        z1 = 0
        z2 = 0
    }
}
