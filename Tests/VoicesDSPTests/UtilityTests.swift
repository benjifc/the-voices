import Testing
@testable import VoicesDSP

@Test func dbConversionsRoundTrip() {
    #expect(abs(dbToGain(-6) - 0.501) < 0.001)
    #expect(abs(gainToDb(dbToGain(-20)) - (-20)) < 0.01)
    #expect(gainToDb(0) == -120)
}

@Test func helpersMeasureSine() {
    let x = sine(440, seconds: 1)
    #expect(abs(estimateFrequency(x[...]) - 440) < 1)
    #expect(abs(rmsDb(sine(440, seconds: 1, amplitude: 0.5)[...]) - (-9.03)) < 0.1)
}
