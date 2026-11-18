import Testing
@testable import VoicesDSP

@Test func enhancementHasNoLatency() {
    for level in EnhancementLevel.allCases {
        let chain = EnhancementChain(level: level)
        var input = [Float](repeating: 0, count: 4800 + 480)
        input[4800] = 0.5
        var output = input
        chain.process(&output)
        let latency = onsetLatency(output, after: 4800)
        #expect(latency <= 2, "nivel \(level): latencia \(latency) muestras")
    }
}

@Test func radioIsLouderThanSoft() {
    func outputLevel(_ level: EnhancementLevel) -> Float {
        let chain = EnhancementChain(level: level)
        // Seno a −24 dBFS RMS (R5): amplitud de pico = RMS · √2.
        var x = sine(300, seconds: 1, amplitude: dbToGain(-24) * Float(2).squareRoot())
        chain.process(&x)
        return rmsDb(x[(x.count - Int(sampleRate / 2))...])
    }
    let soft = outputLevel(.soft)
    let normal = outputLevel(.normal)
    let radio = outputLevel(.radio)
    #expect(radio > normal, "radio \(radio) vs normal \(normal)")
    #expect(normal > soft, "normal \(normal) vs suave \(soft)")
}

@Test func enhancementOutputIsFinite() {
    let chain = EnhancementChain(level: .radio)
    // Ruido blanco a 0 dBFS RMS (R5): amplitud de pico = √3.
    var x = whiteNoise(seconds: 2, amplitude: Float(3).squareRoot())
    chain.process(&x)
    #expect(x.allSatisfy { $0.isFinite })
}

@Test func setLevelMatchesFreshChain() {
    let input = whiteNoise(seconds: 0.3, amplitude: 0.3, seed: 11)
    let switched = EnhancementChain(level: .soft)
    var warmup = input
    switched.process(&warmup)
    switched.setLevel(.radio)
    switched.reset()
    var a = input
    switched.process(&a)

    let fresh = EnhancementChain(level: .radio)
    var b = input
    fresh.process(&b)
    #expect(a == b)
}

@Test func setLevelKeepsAudioFlowing() {
    // Cambiar de nivel a mitad de señal no produce muestras no finitas ni saltos enormes.
    let chain = EnhancementChain(level: .normal)
    var x = sine(300, seconds: 0.4, amplitude: 0.2)
    var first = Array(x[0..<9600])
    var second = Array(x[9600...])
    chain.process(&first)
    chain.setLevel(.radio)
    chain.process(&second)
    x = first + second
    #expect(x.allSatisfy { $0.isFinite })
    #expect(maxStep(x) < 0.5)
}

@Test func levelsHaveSpanishNames() {
    #expect(EnhancementLevel.allCases.map(\.displayName) == ["Suave", "Normal", "Radio"])
    #expect(EnhancementLevel.allCases.map(\.rawValue) == [0, 1, 2])
}
