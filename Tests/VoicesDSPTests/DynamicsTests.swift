import Testing
@testable import VoicesDSP

/// Seno cuyo nivel RMS es `level` dBFS (R5: "señal a X dBFS" = RMS).
private func sineAt(_ freq: Double, seconds: Double, level: Float) -> [Float] {
    sine(freq, seconds: seconds, amplitude: dbToGain(level) * Float(2).squareRoot())
}

/// Ruido blanco uniforme cuyo nivel RMS es `level` dBFS.
private func noiseAt(seconds: Double, level: Float) -> [Float] {
    whiteNoise(seconds: seconds, amplitude: dbToGain(level) * Float(3).squareRoot())
}

private func lastHalfSecond(_ x: [Float]) -> ArraySlice<Float> {
    x[(x.count - Int(sampleRate / 2))...]
}

private let speechGate = GateSettings(
    thresholdDb: -45, rangeDb: -12, attackMs: 1, holdMs: 150, releaseMs: 200)

// MARK: - NoiseGate

@Test func gateAttenuatesNoiseFloor() {
    let gate = NoiseGate(speechGate)
    let input = noiseAt(seconds: 1, level: -60)
    var output = input
    gate.process(&output)
    let outLevel = rmsDb(lastHalfSecond(output))
    #expect(abs(outLevel - (-72)) < 1.5, "salida \(outLevel) dBFS")
}

@Test func gatePassesSpeechLevel() {
    let gate = NoiseGate(speechGate)
    let input = sineAt(300, seconds: 1, level: -20)
    var output = input
    gate.process(&output)
    let gain = rmsDb(lastHalfSecond(output)) - rmsDb(lastHalfSecond(input))
    #expect(abs(gain) < 0.5, "ganancia \(gain) dB")
}

@Test func gateHoldsWordTails() {
    let gate = NoiseGate(speechGate)
    let loud = sineAt(300, seconds: 0.5, level: -20)
    let quiet = sineAt(300, seconds: 0.5, level: -50)
    let input = loud + quiet
    var output = input
    gate.process(&output)
    let start = loud.count
    let window = start..<(start + Int(0.14 * sampleRate))
    let drop = rmsDb(input[window]) - rmsDb(output[window])
    #expect(drop <= 1, "la cola cae \(drop) dB")
}

@Test func gateReopensQuicklyAfterSilence() {
    let gate = NoiseGate(speechGate)
    let silence = noiseAt(seconds: 1, level: -70)
    let speech = sineAt(300, seconds: 0.3, level: -20)
    let input = silence + speech
    var output = input
    gate.process(&output)
    // Pasados 10 ms del inicio de la voz, la puerta ya debe estar abierta.
    let from = silence.count + Int(0.010 * sampleRate)
    let gain = rmsDb(output[from...]) - rmsDb(input[from...])
    #expect(gain > -0.5, "ganancia \(gain) dB")
}

// MARK: - Compressor

private let testCompressor = CompressorSettings(
    thresholdDb: -20, ratio: 4, attackMs: 5, releaseMs: 100, makeupDb: 0)

@Test func compressorReducesAboveThreshold() {
    let loudComp = Compressor(testCompressor)
    var loud = sineAt(1000, seconds: 1, level: -8)
    loudComp.process(&loud)
    let loudOut = rmsDb(lastHalfSecond(loud))
    #expect(abs(loudOut - (-17)) < 1, "salida \(loudOut) dBFS")

    let quietComp = Compressor(testCompressor)
    let quietIn = sineAt(1000, seconds: 1, level: -30)
    var quiet = quietIn
    quietComp.process(&quiet)
    let change = rmsDb(lastHalfSecond(quiet)) - rmsDb(lastHalfSecond(quietIn))
    #expect(abs(change) < 0.5, "cambio \(change) dB")
}

@Test func compressorAppliesMakeupGain() {
    var s = testCompressor
    s.makeupDb = 6
    let comp = Compressor(s)
    let input = sineAt(1000, seconds: 1, level: -30)
    var output = input
    comp.process(&output)
    let change = rmsDb(lastHalfSecond(output)) - rmsDb(lastHalfSecond(input))
    #expect(abs(change - 6) < 0.5, "cambio \(change) dB")
}

// MARK: - DeEsser

@Test func deEsserTamesSibilance() {
    let settings = DeEsserSettings(frequency: 6500, thresholdDb: -30, maxReductionDb: 8)

    let sibilantIn = sineAt(6500, seconds: 1, level: -12)
    var sibilant = sibilantIn
    DeEsser(settings).process(&sibilant)
    let reduction = rmsDb(lastHalfSecond(sibilantIn)) - rmsDb(lastHalfSecond(sibilant))
    // Con la señal en el centro la reducción satura en el máximo (8 dB); se admite
    // un margen numérico mínimo por encima.
    #expect(reduction >= 4 && reduction <= 8.1, "reducción \(reduction) dB")

    let lowIn = sineAt(500, seconds: 1, level: -12)
    var low = lowIn
    DeEsser(settings).process(&low)
    let change = abs(rmsDb(lastHalfSecond(low)) - rmsDb(lastHalfSecond(lowIn)))
    #expect(change <= 0.5, "cambio \(change) dB")
}

// MARK: - Limiter

@Test func limiterNeverExceedsCeiling() {
    let limiter = Limiter()
    #expect(limiter.latencySamples == 48)
    var output = sine(200, seconds: 0.5, amplitude: 4.0)
    limiter.process(&output)
    #expect(peakDb(output[...]) <= -1.0, "pico \(peakDb(output[...])) dBFS")
}

@Test func limiterNeverExceedsCeilingOnBurstsOfNoise() {
    let limiter = Limiter(ceilingDb: -3)
    let quiet = noiseAt(seconds: 0.1, level: -40)
    let burst = whiteNoise(seconds: 0.05, amplitude: 6, seed: 7)
    var output = quiet + burst + quiet
    // Procesado por bloques irregulares para ejercitar el estado entre llamadas.
    var offset = 0
    let sizes = [64, 100, 1, 480, 333]
    var k = 0
    while offset < output.count {
        let n = min(sizes[k % sizes.count], output.count - offset)
        output.withUnsafeMutableBufferPointer {
            limiter.process($0.baseAddress! + offset, frameCount: n)
        }
        offset += n
        k += 1
    }
    #expect(peakDb(output[...]) <= -3.0, "pico \(peakDb(output[...])) dBFS")
}

@Test func limiterIsTransparentBelowCeiling() {
    let limiter = Limiter()
    let input = sineAt(1000, seconds: 0.2, level: -20)
    var output = input
    limiter.process(&output)
    let delay = limiter.latencySamples
    var maxError: Float = 0
    for i in delay..<input.count {
        maxError = max(maxError, abs(output[i] - input[i - delay]))
    }
    #expect(maxError < 1e-6, "error máximo \(maxError)")
}

@Test func limiterResetClearsDelayLine() {
    let limiter = Limiter()
    var loud = sine(200, seconds: 0.05, amplitude: 4.0)
    limiter.process(&loud)
    limiter.reset()
    var silence = [Float](repeating: 0, count: 200)
    limiter.process(&silence)
    #expect(silence.allSatisfy { $0 == 0 })
}
