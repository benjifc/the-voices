import Foundation
@testable import VoicesDSP

func sine(_ freq: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
    let n = Int(seconds * sampleRate)
    return (0..<n).map { i in
        amplitude * Float(sin(2 * Double.pi * freq * Double(i) / sampleRate))
    }
}

private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func whiteNoise(seconds: Double, amplitude: Float, seed: UInt64 = 1) -> [Float] {
    var rng = SplitMix64(state: seed)
    let n = Int(seconds * sampleRate)
    return (0..<n).map { _ in
        let u = Double(rng.next() >> 11) / Double(1 << 53)
        return amplitude * Float(u * 2 - 1)
    }
}

func rmsDb(_ x: ArraySlice<Float>) -> Float {
    guard !x.isEmpty else { return -120 }
    let sum = x.reduce(Float(0)) { $0 + $1 * $1 }
    return gainToDb(sqrtf(sum / Float(x.count)))
}

func peakDb(_ x: ArraySlice<Float>) -> Float {
    gainToDb(x.reduce(Float(0)) { max($0, abs($1)) })
}

/// Cruces por cero ascendentes con interpolación lineal.
func estimateFrequency(_ x: ArraySlice<Float>) -> Double {
    var crossings: [Double] = []
    var prev: Float? = nil
    var idx = 0
    for v in x {
        if let p = prev, p < 0, v >= 0 {
            crossings.append(Double(idx - 1) + Double(-p / (v - p)))
        }
        prev = v
        idx += 1
    }
    guard crossings.count >= 2 else { return 0 }
    let periods = Double(crossings.count - 1)
    return periods * sampleRate / (crossings.last! - crossings.first!)
}

func onsetLatency(_ output: [Float], after silenceSamples: Int, thresholdDb: Float = -40) -> Int {
    let threshold = dbToGain(thresholdDb)
    var i = silenceSamples
    while i < output.count {
        if abs(output[i]) > threshold { return i - silenceSamples }
        i += 1
    }
    return output.count - silenceSamples
}

func maxStep(_ x: [Float]) -> Float {
    var m: Float = 0
    for i in 1..<max(x.count, 1) { m = max(m, abs(x[i] - x[i - 1])) }
    return m
}

#if DEBUG
let isDebugBuild = true
#else
let isDebugBuild = false
#endif
