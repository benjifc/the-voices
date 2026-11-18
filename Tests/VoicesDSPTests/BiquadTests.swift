import Testing
@testable import VoicesDSP

/// Ganancia en dB de un filtro para un seno puro, medida sobre el último 0,5 s de 1 s.
private func gainDb(
    _ kind: BiquadKind, frequency: Float, q: Float, tone: Double
) -> Float {
    let filter = Biquad(kind, frequency: frequency, q: q)
    let input = sine(tone, seconds: 1)
    var output = input
    filter.process(&output)
    let tail = Int(sampleRate / 2)
    let inDb = rmsDb(input[tail...])
    let outDb = rmsDb(output[tail...])
    return outDb - inDb
}

@Test func highPassRemovesRumble() {
    let rumble = gainDb(.highPass, frequency: 80, q: 0.707, tone: 30)
    let voice = gainDb(.highPass, frequency: 80, q: 0.707, tone: 1000)
    #expect(rumble <= -12)
    #expect(voice >= -0.5)
}

@Test func lowPassRemovesHiss() {
    let hiss = gainDb(.lowPass, frequency: 3400, q: 0.707, tone: 8000)
    #expect(hiss <= -12)
}

@Test func peakBoostsAtCenter() {
    let g = gainDb(.peak(gainDb: 6), frequency: 3000, q: 1, tone: 3000)
    #expect(abs(g - 6) < 0.3)
}

@Test func shelvesMoveTheirBand() {
    let low = gainDb(.lowShelf(gainDb: 3), frequency: 150, q: 0.707, tone: 50)
    #expect(abs(low - 3) < 0.5)
    let high = gainDb(.highShelf(gainDb: 3), frequency: 10_000, q: 0.707, tone: 16_000)
    #expect(abs(high - 3) < 0.5)
}

@Test func bandPassPassesCenterAndRejectsFarTones() {
    let center = gainDb(.bandPass, frequency: 1000, q: 2, tone: 1000)
    let far = gainDb(.bandPass, frequency: 1000, q: 2, tone: 100)
    #expect(abs(center) < 0.5)
    #expect(far <= -12)
}

@Test func configureKeepsStateAndSwitchesResponse() {
    let filter = Biquad(.lowPass, frequency: 200, q: 0.707)
    var warmup = sine(1000, seconds: 0.2)
    filter.process(&warmup)
    // Tras reconfigurar a paso alto, 1 kHz debe pasar sin pérdida y sin explotar.
    filter.configure(.highPass, frequency: 80, q: 0.707)
    let input = sine(1000, seconds: 1)
    var output = input
    filter.process(&output)
    let tail = Int(sampleRate / 2)
    #expect(output.allSatisfy { $0.isFinite })
    #expect(abs(rmsDb(output[tail...]) - rmsDb(input[tail...])) < 0.5)
}

@Test func resetClearsState() {
    let filter = Biquad(.lowPass, frequency: 1000, q: 0.707)
    var loud = sine(500, seconds: 0.1, amplitude: 0.9)
    filter.process(&loud)
    filter.reset()
    #expect(filter.processSample(0) == 0)
}

@Test func processSampleMatchesBlockProcessing() {
    let a = Biquad(.peak(gainDb: 4), frequency: 2000, q: 1.2)
    let b = Biquad(.peak(gainDb: 4), frequency: 2000, q: 1.2)
    let input = whiteNoise(seconds: 0.05, amplitude: 0.5)
    var block = input
    a.process(&block)
    let perSample = input.map { b.processSample($0) }
    #expect(block == perSample)
}
