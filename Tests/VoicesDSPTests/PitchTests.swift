import Foundation
import Testing
@testable import VoicesDSP

// MARK: - PitchShifter

private func shift(_ input: [Float], semitones: Float) -> [Float] {
    let shifter = PitchShifter()
    shifter.setSemitones(semitones)
    var output = input
    shifter.process(&output)
    return output
}

@Test func shifterRaisesFifth() {
    let output = shift(sine(200, seconds: 2), semitones: 7)
    let estimated = estimateFrequency(output[Int(sampleRate)...])
    let expected = 200 * pow(2, 7.0 / 12)  // ≈ 299.7 Hz
    #expect(abs(estimated - expected) / expected < 0.03, "estimada \(estimated) Hz")
}

@Test func shifterLowersOctave() {
    let output = shift(sine(400, seconds: 2), semitones: -12)
    let estimated = estimateFrequency(output[Int(sampleRate)...])
    // Tolerancia 8 % en lugar del 3 % de los demás tests: con dos lecturas separadas media
    // ventana (768 muestras = 6,4 períodos de 400 Hz) el traspaso de grano añade un sesgo
    // de frecuencia de hasta 0,5·|ratio−1|·fs/768 = 15,6 Hz (7,8 % de 200 Hz); aquí son
    // 12,5 Hz. Es propio del algoritmo (ver `shifterBiasFollowsGranularModel`), no un fallo.
    #expect(abs(estimated - 200) / 200 < 0.08, "estimada \(estimated) Hz")
}

/// El sesgo de frecuencia del cambio de tono granular es predecible: en cada traspaso entre
/// lecturas (separadas D = ventana/2) la fase salta D·ω; si no es múltiplo de 2π, la
/// frecuencia media se desplaza `−frac(f·D/fs)·(ratio−1)·fs/D`, con `frac` en (−½, ½].
@Test func shifterBiasFollowsGranularModel() {
    let d = 768.0
    let cases: [(freq: Double, semitones: Float)] = [
        (200, 7), (400, -12), (150, -4), (250, 3), (400, 7), (120, 12),
    ]
    for c in cases {
        let output = shift(sine(c.freq, seconds: 3), semitones: c.semitones)
        let estimated = Double(estimateFrequency(output[Int(2 * sampleRate)...]))
        let ratio = pow(2.0, Double(c.semitones) / 12)
        var frac = (c.freq * d / sampleRate).truncatingRemainder(dividingBy: 1)
        if frac > 0.5 { frac -= 1 }
        let predicted = ratio * c.freq - frac * (ratio - 1) * sampleRate / d
        #expect(
            abs(estimated - predicted) < 0.5,
            "\(c.freq) Hz, \(c.semitones) st: medida \(estimated), modelo \(predicted)")
    }
}

private func burstLatency(silence: Int, ratio: Float) -> Int {
    let shifter = PitchShifter()
    shifter.ratio = ratio
    var input = [Float](repeating: 0, count: silence)
    input += sine(440, seconds: 0.1, amplitude: 0.5)
    shifter.process(&input)
    return onsetLatency(input, after: silence)
}

@Test func shifterLatencyWithinBudget() {
    let latency = burstLatency(silence: 9600, ratio: 1.5)
    #expect(latency <= 1200, "latencia \(latency) muestras")
}

@Test func shifterLatencyIsBoundedForAnyGrainPhase() {
    // La fase de los granos depende del instante en que llega la señal: se barren varias.
    for k in 0..<24 {
        let silence = 9600 + k * 131
        let latency = burstLatency(silence: silence, ratio: 1.5)
        #expect(latency <= 1200, "silencio \(silence): latencia \(latency) muestras")
    }
}

@Test func shifterNominalLatencyIsHalfWindow() {
    #expect(PitchShifter().latencySamples == 768)
    #expect(PitchShifter(windowSamples: 1024).latencySamples == 512)
}

@Test func shifterAtUnityRatioIsPureDelay() {
    let shifter = PitchShifter()
    shifter.ratio = 1
    let input = whiteNoise(seconds: 0.2, amplitude: 0.5, seed: 3)
    var output = input
    shifter.process(&output)
    let delay = shifter.latencySamples
    var maxError: Float = 0
    for i in delay..<input.count {
        maxError = max(maxError, abs(output[i] - input[i - delay]))
    }
    #expect(maxError < 1e-5, "error máximo \(maxError)")
}

@Test func shifterAcceptsRatioChangesPerSample() {
    let shifter = PitchShifter()
    let input = sine(300, seconds: 1, amplitude: 0.5)
    var output = [Float](repeating: 0, count: input.count)
    for i in 0..<input.count {
        shifter.ratio = 1 + 0.2 * sinf(Float(i) * 0.001)
        output[i] = shifter.processSample(input[i])
    }
    #expect(output.allSatisfy { $0.isFinite })
    // Las dos lecturas suman ganancia 1: la salida nunca supera la amplitud de entrada.
    #expect(output.allSatisfy { abs($0) <= 0.5 + 1e-4 })
}

@Test func shifterClampsRatio() {
    let shifter = PitchShifter()
    shifter.ratio = 10
    var x = sine(300, seconds: 0.2)
    shifter.process(&x)
    #expect(x.allSatisfy { $0.isFinite })
    shifter.setSemitones(-48)
    shifter.process(&x)
    #expect(x.allSatisfy { $0.isFinite })
}

// MARK: - PitchDetector

private func pushAll(_ detector: PitchDetector, _ x: [Float], chunk: Int = 256) {
    x.withUnsafeBufferPointer { buf in
        var offset = 0
        while offset < buf.count {
            let n = min(chunk, buf.count - offset)
            detector.push(buf.baseAddress! + offset, frameCount: n)
            offset += n
        }
    }
}

@Test func detectorFindsVoiceRange() {
    for f in [82.0, 110, 220, 440, 880] {
        let detector = PitchDetector()
        pushAll(detector, sine(f, seconds: 0.5, amplitude: 0.5))
        guard let estimated = detector.frequency else {
            Issue.record("sin frecuencia para \(f) Hz")
            continue
        }
        #expect(abs(Double(estimated) - f) / f < 0.01, "\(f) Hz → \(estimated) Hz")
        #expect(detector.confidence > 0.9)
    }
}

@Test func detectorIgnoresNoise() {
    let detector = PitchDetector()
    // Ruido blanco a −20 dBFS RMS (R5): amplitud de pico = RMS · √3.
    let noise = whiteNoise(seconds: 2, amplitude: dbToGain(-20) * Float(3).squareRoot())
    var hops = 0
    var detections = 0
    noise.withUnsafeBufferPointer { buf in
        var offset = 0
        while offset + 256 <= buf.count {
            detector.push(buf.baseAddress! + offset, frameCount: 256)
            offset += 256
            if offset > 4096 {  // ventana ya llena
                hops += 1
                if detector.frequency != nil { detections += 1 }
            }
        }
    }
    #expect(hops > 300)
    #expect(Double(detections) / Double(hops) <= 0.10, "\(detections) de \(hops) hops con tono")
}

@Test func detectorIgnoresSilence() {
    let detector = PitchDetector()
    let zeros = [Float](repeating: 0, count: 256)
    zeros.withUnsafeBufferPointer { buf in
        for _ in 0..<64 {
            detector.push(buf.baseAddress!, frameCount: 256)
            #expect(detector.frequency == nil)
        }
    }
}

@Test func detectorIgnoresVeryQuietTone() {
    let detector = PitchDetector()
    // −60 dBFS RMS: por debajo del umbral de −50 dBFS.
    pushAll(detector, sine(220, seconds: 0.5, amplitude: dbToGain(-60) * Float(2).squareRoot()))
    #expect(detector.frequency == nil)
}

@Test func detectorResultDoesNotDependOnChunkSize() {
    let x = sine(196, seconds: 0.5, amplitude: 0.4)
    let a = PitchDetector()
    let b = PitchDetector()
    pushAll(a, x, chunk: 256)
    pushAll(b, x, chunk: 1)
    #expect(a.frequency != nil)
    #expect(a.frequency == b.frequency)
}

@Test func detectorPicksFundamentalOfHarmonicVoice() {
    // Fundamental débil con armónicos fuertes: YIN no debe saltar a una octava.
    let f0 = 150.0
    let n = Int(0.5 * sampleRate)
    let x: [Float] = (0..<n).map { i in
        let t = Double(i) / sampleRate
        var v = 0.15 * sin(2 * .pi * f0 * t)
        for h in 2...6 { v += 0.12 * sin(2 * .pi * f0 * Double(h) * t + Double(h)) }
        return Float(v)
    }
    let detector = PitchDetector()
    pushAll(detector, x)
    let estimated = Double(detector.frequency ?? 0)
    #expect(abs(estimated - f0) / f0 < 0.01, "estimada \(estimated) Hz")
}
