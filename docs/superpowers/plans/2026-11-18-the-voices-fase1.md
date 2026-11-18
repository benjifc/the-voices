# The Voices — Fase 1: Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App de barra de menús para macOS que procesa en tiempo real la voz del RØDE NT-USB+ (voz mejorada, 12 personajes con efectos clásicos, autotune) y la entrega a BlackHole 2ch para usarla como micrófono en cualquier app.

**Architecture:** Paquete SwiftPM con tres librerías y un ejecutable. `VoicesDSP` contiene todo el DSP puro: sin Core Audio, probado con señales sintéticas. `VoicesAudio` contiene Core Audio: dispositivos, dos AUHAL (entrada y salida) unidos por un buffer circular con compensación de deriva, y el supervisor de reconexión. `VoicesKit` contiene el estado de la app, las preferencias y el plist de launchd, todo probable sin interfaz. `TheVoices` es la app SwiftUI `MenuBarExtra` y los atajos globales. Un script empaqueta el binario en `The Voices.app`.

**Tech Stack:** Swift 6.4 (modo de lenguaje 6), SwiftPM, SwiftUI, Core Audio / AudioToolbox (AUHAL), Accelerate (vDSP), módulo `Synchronization` (`Atomic`), Swift Testing, librería [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) para atajos globales y su grabador en Ajustes.

**Spec:** `docs/superpowers/specs/2026-11-18-the-voices-design.md`

## Global Constraints

- Plataforma: macOS 15 como mínimo en `Package.swift` (`.macOS(.v15)`); se desarrolla y prueba en macOS 27.0.1, Mac mini M4.
- Frecuencia de trabajo: **48 000 Hz**, mono en todo el DSP; la salida a BlackHole es estéreo con la misma señal en L y R.
- Retardo añadido (entrada → BlackHole): **voz mejorada ≤ 20 ms**; **personajes y autotune ≤ 50 ms**.
- CPU de la app en uso normal: **< 15 % de un núcleo**.
- Cambio de preset audible en **< 100 ms** desde el atajo; cambios con fundido (sin "pop").
- Hilo de audio en tiempo real: sin asignaciones de memoria, sin locks, sin `print`, sin llamadas a Swift Concurrency. La comunicación con el hilo principal se hace solo mediante `Atomic`.
- La app **nunca** usa como entrada un dispositivo cuyo nombre o UID contenga `BlackHole`.
- La app **siempre arranca en "Mi voz mejorada"**, sin personaje ni bypass. El modo activo no se persiste.
- Tecla de pánico = bypass total (voz sin procesar), que se mantiene hasta elegir otro modo.
- Sin grabación integrada, sin IA, sin driver propio, sin App Store (Fase 1).
- Nombre visible: **The Voices**. Bundle id: `local.thevoices.app`. Etiqueta launchd: `local.thevoices.agent`.
- Textos de la interfaz en **español**.
- Autoría: commits firmados solo como "Benjamin Fernandez Carrasco"; ningún fichero, comentario ni mensaje de commit menciona herramientas de IA. Los ficheros de configuración personales del editor se excluyen con `.git/info/exclude`, no con `.gitignore`.
- Los tests de rendimiento se ejecutan en release: `swift test -c release`.

## Review Focus

1. **Desconectar el RØDE (o BlackHole) en mitad de la llamada**: la app debe mostrar el error en el icono, enviar una notificación (Zoom puede estar a pantalla completa) y reconectarse sola al volver el dispositivo. Test en Task 10 (`supervisorRestartsWhenInputReturns`).
2. **Relojes distintos entre RØDE y BlackHole**: tras una hora, la deriva no debe provocar cortes ni chasquidos. Test en Task 9 (`bridgeSurvivesOneHourOfDrift`).
3. **Pulsar atajos muy seguidos** (cambiar de personaje 10 veces en un segundo): sin "pop", sin chains a medio fundir y sin NaN. Test en Task 8 (`rapidModeChangesStayContinuous`).
4. **Gritar o dar un golpe al micro**: la salida nunca pasa de −1 dBFS en ningún modo salvo bypass. Test en Task 8 (`loudInputNeverExceedsCeiling`).
5. **Silencio largo y ruido de fondo** (ventilador, teclado): la puerta no debe cortar finales de palabra ni bombear, y el autotune no debe inventarse notas con ruido. Tests en Task 3 (`gateHoldsWordTails`) y Task 6 (`autotunePassesUnvoicedThrough`).

---

## Estructura de ficheros

```
Package.swift
Support/Info.plist                     # bundle de la app (LSUIElement, micrófono)
scripts/build-app.sh                   # compila release y monta "build/The Voices.app"
scripts/install.sh                     # copia a ~/Applications
README.md
Sources/VoicesDSP/
  AudioEffect.swift                    # protocolo + utilidades dB
  Biquad.swift
  Dynamics/NoiseGate.swift
  Dynamics/Compressor.swift
  Dynamics/DeEsser.swift
  Dynamics/Limiter.swift
  EnhancementChain.swift
  Pitch/PitchShifter.swift
  Pitch/PitchDetector.swift
  Pitch/AutoTune.swift
  Effects/Modulation.swift             # LFO, RingModulator, Flanger
  Effects/Distortion.swift             # Saturation, Bitcrusher, NoiseSource
  Effects/Space.swift                  # Delay, Reverb
  Characters/PresetID.swift
  Characters/CharacterChain.swift
  VoiceProcessor.swift
Sources/VoicesAudio/
  ClockBridge.swift
  AudioDevice.swift                    # modelo + DeviceCatalog (consulta Core Audio)
  DeviceSelection.swift                # lógica pura de elección de dispositivos
  DeviceChangeListener.swift
  VoiceEngine.swift                    # AUHAL entrada / salida / monitor
  EngineSupervisor.swift
Sources/VoicesKit/
  Preferences.swift
  AppModel.swift
  LaunchAgent.swift
  StatusIcon.swift
Sources/TheVoices/
  TheVoicesApp.swift
  MenuContentView.swift
  SettingsView.swift
  Hotkeys.swift
  Notifier.swift
Tests/VoicesDSPTests/  (Helpers.swift + un fichero por task)
Tests/VoicesAudioTests/
Tests/VoicesKitTests/
```

---

### Task 1: Repositorio, paquete y app vacía que arranca

**Files:**
- Create: `Package.swift`, `Support/Info.plist`, `scripts/build-app.sh`, `scripts/install.sh`, `README.md`, `.gitignore`
- Create: `Sources/VoicesDSP/AudioEffect.swift`, `Sources/VoicesAudio/ClockBridge.swift` (vacío salvo `import`), `Sources/VoicesKit/Preferences.swift` (vacío salvo `import`), `Sources/TheVoices/TheVoicesApp.swift`
- Test: `Tests/VoicesDSPTests/Helpers.swift`, `Tests/VoicesDSPTests/UtilityTests.swift`

**Interfaces:**
- Produces (en `VoicesDSP`):
  - `public let sampleRate: Double = 48_000`
  - `public protocol AudioEffect: AnyObject { func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int); func reset() }`
  - `extension AudioEffect { public func process(_ samples: inout [Float]) }` (solo para tests y utilidades fuera del hilo de audio)
  - `public func dbToGain(_ db: Float) -> Float`, `public func gainToDb(_ gain: Float) -> Float` (con suelo en −120 dB)
  - `public func timeConstantCoefficient(ms: Float, sampleRate: Double) -> Float` = `exp(-1 / (ms * 0.001 * sampleRate))`
- Produces (helpers de test, en `Tests/VoicesDSPTests/Helpers.swift`):
  - `func sine(_ freq: Double, seconds: Double, amplitude: Float = 0.5) -> [Float]`
  - `func whiteNoise(seconds: Double, amplitude: Float, seed: UInt64 = 1) -> [Float]` (generador determinista)
  - `func rmsDb(_ x: ArraySlice<Float>) -> Float`, `func peakDb(_ x: ArraySlice<Float>) -> Float`
  - `func estimateFrequency(_ x: ArraySlice<Float>) -> Double` (cruces por cero ascendentes con interpolación lineal)
  - `func onsetLatency(_ output: [Float], after silenceSamples: Int, thresholdDb: Float = -40) -> Int` (primer índice ≥ `silenceSamples` con |x| por encima del umbral, menos `silenceSamples`)
  - `func maxStep(_ x: [Float]) -> Float` (máximo |x[n]−x[n−1]|, para detectar "pops")
  - `let isDebugBuild: Bool` (`#if DEBUG` → true), para saltar los tests de rendimiento en debug

- [ ] **Step 1: Iniciar el repositorio.** `git init`; exclusiones personales en `.git/info/exclude`; `.gitignore` con `.build/`, `build/`, `.swiftpm/`, `*.xcodeproj`, `.DS_Store`.
- [ ] **Step 2: `Package.swift`.** `swift-tools-version: 6.0`; plataformas `.macOS(.v15)`; dependencia `KeyboardShortcuts` `from: "2.0.0"`; targets `VoicesDSP`, `VoicesAudio` (→ VoicesDSP), `VoicesKit` (→ VoicesDSP, VoicesAudio), ejecutable `TheVoices` (→ las tres + KeyboardShortcuts); test targets `VoicesDSPTests`, `VoicesAudioTests`, `VoicesKitTests`. Linker settings de `VoicesAudio`: `CoreAudio`, `AudioToolbox`. `VoicesDSP` enlaza `Accelerate`.
- [ ] **Step 3: Escribir los tests que fallan** en `UtilityTests.swift`:
  - `dbConversionsRoundTrip`: `dbToGain(-6)` ≈ 0.501 (±0.001); `gainToDb(dbToGain(-20))` ≈ −20 (±0.01); `gainToDb(0)` == −120.
  - `helpersMeasureSine`: `estimateFrequency(sine(440, seconds: 1)[...])` ≈ 440 (±1); `rmsDb` de seno con amplitud 0.5 ≈ −9.03 (±0.1).
- [ ] **Step 4: Ejecutar `swift test` → FAIL** (símbolos sin definir).
- [ ] **Step 5: Implementar `AudioEffect.swift` y los helpers.**
- [ ] **Step 6: `swift test` → PASS.**
- [ ] **Step 7: App mínima.** `TheVoicesApp`: `@main struct TheVoicesApp: App` con `MenuBarExtra("The Voices", systemImage: "waveform")` que contiene solo "Salir de The Voices". `Support/Info.plist`: `CFBundleIdentifier local.thevoices.app`, `CFBundleName The Voices`, `CFBundleExecutable TheVoices`, `LSUIElement true`, `LSMinimumSystemVersion 15.0`, `NSMicrophoneUsageDescription "The Voices necesita el micrófono para procesar tu voz en tiempo real."`.
- [ ] **Step 8: `scripts/build-app.sh`.** `swift build -c release`; crea `build/The Voices.app/Contents/{MacOS,Resources}`; copia el binario e `Info.plist`; copia todos los `*.bundle` de `.build/release/` en `Contents/Resources/` (recursos de KeyboardShortcuts); `codesign --force --deep --sign - "build/The Voices.app"`. `scripts/install.sh`: ejecuta el build y copia a `~/Applications/The Voices.app` (reemplazando).
- [ ] **Step 9: Verificar.** `./scripts/build-app.sh && open "build/The Voices.app"` → aparece el icono de onda en la barra de menús y "Salir" cierra la app.
- [ ] **Step 10: README inicial** (qué es, requisitos: BlackHole 2ch vía `brew install blackhole-2ch`, cómo compilar e instalar).
- [ ] **Step 11: Commit** con el spec y el plan incluidos: `git add -A && git commit -m "chore: estructura inicial del proyecto"`.

---

### Task 2: Filtros biquad

**Files:** Create `Sources/VoicesDSP/Biquad.swift` · Test `Tests/VoicesDSPTests/BiquadTests.swift`

**Interfaces:**
- Produces: `public enum BiquadKind: Sendable { case lowPass, highPass, bandPass, peak(gainDb: Float), lowShelf(gainDb: Float), highShelf(gainDb: Float) }`
- Produces: `public final class Biquad: AudioEffect { public init(_ kind: BiquadKind, frequency: Float, q: Float); public func configure(_ kind: BiquadKind, frequency: Float, q: Float); public func processSample(_ x: Float) -> Float }`. Coeficientes del RBJ Audio EQ Cookbook, forma directa transpuesta II. `configure` no asigna memoria (se puede llamar desde el hilo de audio) y conserva el estado.

- [ ] **Step 1: Tests que fallan:**
  - `highPassRemovesRumble`: HPF 80 Hz, Q 0.707; seno de 30 Hz → atenuación ≥ 12 dB; seno de 1 kHz → atenuación ≤ 0.5 dB (medir RMS sobre el último 0.5 s de 1 s).
  - `lowPassRemovesHiss`: LPF 3400 Hz; seno de 8 kHz atenuado ≥ 12 dB.
  - `peakBoostsAtCenter`: peak +6 dB a 3 kHz, Q 1; seno de 3 kHz ganancia ≈ +6 dB (±0.3).
  - `shelvesMoveTheirBand`: lowShelf +3 dB a 150 Hz → 50 Hz sube ≈ 3 dB (±0.5); highShelf +3 dB a 10 kHz → 16 kHz sube ≈ 3 dB (±0.5).
- [ ] **Step 2: `swift test --filter BiquadTests` → FAIL.**
- [ ] **Step 3: Implementar `Biquad`.**
- [ ] **Step 4: `swift test --filter BiquadTests` → PASS.**
- [ ] **Step 5: Commit** `feat(dsp): filtros biquad`.

---

### Task 3: Dinámica — puerta, compresor, de-esser y limitador

**Files:** Create `Sources/VoicesDSP/Dynamics/{NoiseGate,Compressor,DeEsser,Limiter}.swift` · Test `Tests/VoicesDSPTests/DynamicsTests.swift`

**Interfaces:**
- Produces: `public struct GateSettings: Sendable { thresholdDb, rangeDb, attackMs, holdMs, releaseMs: Float }` y `public final class NoiseGate: AudioEffect { public init(_ s: GateSettings); public func update(_ s: GateSettings) }`. Expansor: por debajo del umbral, la ganancia baja hasta `rangeDb` (no a silencio); el detector es un envolvente de pico; durante `holdMs` tras caer por debajo del umbral, la ganancia no baja.
- Produces: `public struct CompressorSettings: Sendable { thresholdDb, ratio, attackMs, releaseMs, makeupDb: Float }` y `public final class Compressor: AudioEffect { public init(_ s: CompressorSettings); public func update(_ s: CompressorSettings) }`. Feed-forward, detector RMS (ventana ~10 ms), rodilla dura.
- Produces: `public struct DeEsserSettings: Sendable { frequency, thresholdDb, maxReductionDb: Float }` y `public final class DeEsser: AudioEffect`. Algoritmo: `bp = bandPass(x, frequency, Q 1.0)`; envolvente de `bp`; `g` = reducción (hasta `maxReductionDb`) cuando la envolvente supera el umbral, ratio 4; salida `y = x − (1 − g)·bp`. Latencia cero.
- Produces: `public final class Limiter: AudioEffect { public init(ceilingDb: Float = -1, lookaheadMs: Float = 1, releaseMs: Float = 50); public var latencySamples: Int { get } }`. Lookahead con línea de retardo y ganancia = mínimo de la ventana; garantiza `|y| ≤ dbToGain(ceilingDb)`.

- [ ] **Step 1: Tests que fallan:**
  - `gateAttenuatesNoiseFloor`: ruido a −60 dBFS con `GateSettings(thresholdDb: -45, rangeDb: -12, attackMs: 1, holdMs: 150, releaseMs: 200)` → salida ≈ −72 dBFS (±1.5) tras 0.5 s.
  - `gatePassesSpeechLevel`: seno de 300 Hz a −20 dBFS → ganancia ≈ 0 dB (±0.5).
  - `gateHoldsWordTails` (Review Focus 5): seno a −20 dBFS durante 0.5 s seguido de seno a −50 dBFS → durante los primeros 140 ms tras el cambio, la salida está a ≤ 1 dB por debajo de la entrada.
  - `compressorReducesAboveThreshold`: threshold −20, ratio 4, makeup 0; seno a −8 dBFS → salida ≈ −17 dBFS (±1) en régimen estable; seno a −30 dBFS → sin cambio (±0.5).
  - `deEsserTamesSibilance`: frecuencia 6500, umbral −30, máx −8 dB; seno de 6.5 kHz a −12 dBFS se reduce entre 4 y 8 dB; seno de 500 Hz a −12 dBFS cambia ≤ 0.5 dB.
  - `limiterNeverExceedsCeiling`: seno de 200 Hz con amplitud 4.0 (≈ +12 dBFS) → `peakDb(salida) ≤ -1.0`; `latencySamples == 48`.
- [ ] **Step 2: `swift test --filter DynamicsTests` → FAIL.**
- [ ] **Step 3: Implementar las cuatro clases.**
- [ ] **Step 4: `swift test --filter DynamicsTests` → PASS.**
- [ ] **Step 5: Commit** `feat(dsp): puerta, compresor, de-esser y limitador`.

---

### Task 4: Cadena "Mi voz mejorada"

**Files:** Create `Sources/VoicesDSP/EnhancementChain.swift` · Test `Tests/VoicesDSPTests/EnhancementTests.swift`

**Interfaces:**
- Consumes: `Biquad`, `NoiseGate`, `Compressor`, `DeEsser` (Tasks 2–3).
- Produces: `public enum EnhancementLevel: Int, CaseIterable, Sendable { case soft = 0, normal = 1, radio = 2 }` con `public var displayName: String` ("Suave", "Normal", "Radio").
- Produces: `public final class EnhancementChain: AudioEffect { public init(level: EnhancementLevel); public func setLevel(_ level: EnhancementLevel) }`. Orden: HPF → puerta → lowShelf → peak (barro) → peak (presencia) → highShelf → compresor → de-esser. **Sin limitador** (va al final de `VoiceProcessor`). `setLevel` es seguro en el hilo de audio (solo recalcula coeficientes).

Valores (Suave / Normal / Radio):

| Etapa | Suave | Normal | Radio |
|---|---|---|---|
| HPF (Q 0.707) | 80 Hz | 80 Hz | 90 Hz |
| Puerta umbral / rango | −50 / −10 dB | −45 / −12 dB | −42 / −15 dB |
| Puerta attack/hold/release | 1 / 150 / 200 ms | igual | igual |
| lowShelf 150 Hz | +1 dB | +2 dB | +3 dB |
| peak 300 Hz Q 1 | −1 dB | −2 dB | −3 dB |
| peak 3 kHz Q 1 | +1.5 dB | +2.5 dB | +4 dB |
| highShelf 10 kHz | +1 dB | +2 dB | +3 dB |
| Compresor umbral / ratio | −20 dB / 2 | −22 dB / 3 | −26 dB / 4 |
| Compresor attack / release / makeup | 10 / 120 ms / +2 dB | 8 / 100 ms / +4 dB | 5 / 80 ms / +7 dB |
| De-esser | 6500 Hz, −30 dB, −6 dB | 6500 Hz, −30 dB, −8 dB | 6500 Hz, −32 dB, −10 dB |

- [ ] **Step 1: Tests que fallan:**
  - `enhancementHasNoLatency`: para cada nivel, impulso tras 4800 muestras de silencio → `onsetLatency ≤ 2` muestras.
  - `radioIsLouderThanSoft`: seno de 300 Hz a −24 dBFS → RMS de salida Radio > Normal > Suave.
  - `enhancementOutputIsFinite`: ruido blanco a 0 dBFS durante 2 s en Radio → todas las muestras son finitas.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test --filter EnhancementTests`).
- [ ] **Step 5: Commit** `feat(dsp): cadena de voz mejorada con tres niveles`.

---

### Task 5: Cambio y detección de tono

**Files:** Create `Sources/VoicesDSP/Pitch/{PitchShifter,PitchDetector}.swift` · Test `Tests/VoicesDSPTests/PitchTests.swift`

**Interfaces:**
- Produces: `public final class PitchShifter: AudioEffect { public init(windowSamples: Int = 1536); public var ratio: Float /* 0.5…2.0, se puede cambiar por muestra */; public func setSemitones(_ s: Float) }`. Algoritmo granular de línea de retardo con dos lecturas desfasadas media ventana y fundido con ventana de Hann. La lectura avanza a velocidad `ratio`, con interpolación lineal. Cambia tono y formantes a la vez, y eso es lo que se busca para ardilla, gigante y monstruo. Latencia media ≈ ventana/2 (16 ms).
- Produces: `public final class PitchDetector { public init(minHz: Float = 70, maxHz: Float = 1000, windowSamples: Int = 2048, hopSamples: Int = 256); public func push(_ x: UnsafePointer<Float>, frameCount: Int); public private(set) var frequency: Float? /* nil si no hay voz */ ; public private(set) var confidence: Float }`. YIN con umbral 0.15, analizado sobre señal diezmada ×2 (24 kHz) y diferencia acelerada con vDSP. Devuelve `nil` si `confidence < 0.85` o si el RMS de la ventana es < −50 dBFS. Buffers preasignados.

- [ ] **Step 1: Tests que fallan:**
  - `shifterRaisesFifth`: `setSemitones(7)`; seno de 200 Hz durante 2 s → frecuencia estimada en el último segundo ≈ 299.7 Hz (±3 %).
  - `shifterLowersOctave`: `setSemitones(-12)`; 400 Hz → ≈ 200 Hz (±3 %).
  - `shifterLatencyWithinBudget`: seno burst tras 9600 muestras de silencio, ratio 1.5 → `onsetLatency ≤ 1200` (25 ms).
  - `detectorFindsVoiceRange`: para 82, 110, 220, 440 y 880 Hz, el detector devuelve la frecuencia con error ±1 %.
  - `detectorIgnoresNoise`: ruido blanco a −20 dBFS → `frequency == nil` en ≥ 90 % de los hops.
  - `detectorIgnoresSilence`: ceros → siempre `nil`.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test --filter PitchTests`).
- [ ] **Step 5: Commit** `feat(dsp): cambio de tono granular y detector YIN`.

---

### Task 6: Autotune y escalas

**Files:** Create `Sources/VoicesDSP/Pitch/AutoTune.swift` · Test `Tests/VoicesDSPTests/AutoTuneTests.swift`

**Interfaces:**
- Consumes: `PitchShifter`, `PitchDetector` (Task 5).
- Produces: `public enum ScaleKind: Int, CaseIterable, Sendable { case major = 0, minor = 1, chromatic = 2 }` con `displayName` ("Mayor", "Menor", "Cromática").
- Produces: `public func nearestScaleFrequency(to hz: Float, key: Int /* 0 = Do … 11 = Si */, scale: ScaleKind) -> Float`. Afinación A4 = 440 Hz; intervalos de mayor `[0,2,4,5,7,9,11]` y de menor natural `[0,2,3,5,7,8,10]`.
- Produces: `public final class AutoTune: AudioEffect { public init(retuneMs: Float); public func setScale(key: Int, scale: ScaleKind) }`. En cada hop: si hay frecuencia detectada, `target = nearestScaleFrequency`; el ratio objetivo es `target/detected`. El ratio real se suaviza con constante `retuneMs` (0 = instantáneo); sin voz, el ratio vuelve a 1 con 50 ms.

- [ ] **Step 1: Tests que fallan:**
  - `nearestNoteInCMajor`: `nearestScaleFrequency(to: 450, key: 0, scale: .major)` ≈ 440; `(to: 285, key: 0, .major)` ≈ 293.66 (Re4, porque Do#4 no está en Do mayor); `(to: 285, key: 0, .chromatic)` ≈ 277.18.
  - `hardTuneSnapsToNote`: `retuneMs: 0`, Do mayor; seno de 450 Hz durante 2 s → último segundo ≈ 440 Hz (±1 %).
  - `softTuneMovesGradually`: `retuneMs: 50`; los primeros 20 ms tras el inicio de voz siguen más cerca de 450 Hz que de 440 Hz.
  - `autotunePassesUnvoicedThrough` (Review Focus 5): ruido blanco a −30 dBFS → RMS de salida dentro de ±1 dB del de entrada y ratio efectivo 1.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test --filter AutoTuneTests`).
- [ ] **Step 5: Commit** `feat(dsp): autotune con tonalidad y escala`.

---

### Task 7: Efectos de color y personajes

**Files:** Create `Sources/VoicesDSP/Effects/{Modulation,Distortion,Space}.swift`, `Sources/VoicesDSP/Characters/{PresetID,CharacterChain}.swift` · Test `Tests/VoicesDSPTests/EffectsTests.swift`, `Tests/VoicesDSPTests/CharacterTests.swift`

**Interfaces:**
- Produces (efectos, todos `AudioEffect`):
  - `LFO` (struct: `init(rateHz:)`, `mutating func next() -> Float` en −1…1, seno).
  - `RingModulator(frequency: Float, depth: Float)`: `y = x·(1 − depth + depth·sin(2πft))`.
  - `Flanger(minDelayMs: Float, maxDelayMs: Float, rateHz: Float, feedback: Float, mix: Float)`.
  - `Saturation(drive: Float /* 0…1 */)`: `tanh` con compensación de ganancia para que un seno a −20 dBFS conserve ±1 dB.
  - `Bitcrusher(bits: Int, downsample: Int)`.
  - `NoiseSource(levelDb: Float)`: suma ruido blanco determinista.
  - `Delay(timeMs: Float, feedback: Float, mix: Float)`: buffer preasignado de 1 s.
  - `Reverb(roomSize: Float, damping: Float, mix: Float)`: Freeverb (8 combs + 4 allpass, retardos escalados a 48 kHz) en mono.
- Produces: `public enum PresetID: Int, CaseIterable, Sendable { case ardilla, gigante, monstruo, robot, alien, radio, telefono, megafono, cueva, fantasma, autotuneSuave, autotuneExtremo }` con `displayName` ("Ardilla", "Gigante", "Monstruo", "Robot", "Alien", "Radio antigua", "Teléfono", "Megáfono", "Cueva", "Fantasma", "Autotune suave", "Autotune extremo") y `symbolName` (SF Symbol para el menú, a criterio del implementador).
- Produces: `public final class CharacterChain: AudioEffect { public init(preset: PresetID); public var mix: Float /* 0…1, por defecto 1 */; public func setScale(key: Int, scale: ScaleKind) /* no-op salvo autotune */ }`. `y = (1 − mix)·x + mix·wet(x)`, con `x` retrasado lo mismo que `wet` cuando hay latencia, para no producir peine.

Recetas (en orden de proceso):

| Preset | Cadena |
|---|---|
| ardilla | PitchShifter +7 st |
| gigante | PitchShifter −5 st → lowShelf 200 Hz +3 dB |
| monstruo | PitchShifter −8 st → lowShelf 200 Hz +3 dB → Saturation 0.4 |
| robot | RingModulator 60 Hz depth 0.8 → Bitcrusher 8 bits, ×2 |
| alien | PitchShifter +3 st con ratio modulado ±2 st por LFO de 5 Hz → Flanger 1–5 ms, 0.3 Hz, fb 0.6, mix 0.5 |
| radio | HPF 400 Hz → LPF 3000 Hz → Saturation 0.5 → NoiseSource −45 dB |
| telefono | HPF 300 Hz → LPF 3400 Hz → Saturation 0.2 |
| megafono | HPF 600 Hz → LPF 4000 Hz → peak 2 kHz +6 dB Q 1 → Saturation 0.7 |
| cueva | Delay 280 ms fb 0.35 mix 0.3 → Reverb room 0.85 damp 0.4 mix 0.35 |
| fantasma | HPF 200 Hz → mezcla 50 % de una copia con PitchShifter +0.3 st → Reverb room 0.95 damp 0.3 mix 0.5 |
| autotuneSuave | AutoTune retuneMs 50 |
| autotuneExtremo | AutoTune retuneMs 0 |

- [ ] **Step 1: Tests que fallan (`EffectsTests`):**
  - `saturationKeepsQuietLevel`: seno a −20 dBFS, drive 0.7 → RMS ±1 dB.
  - `bitcrusherQuantizes`: 4 bits, ×1 → la salida toma como máximo 16 valores distintos.
  - `delayEchoArrivesOnTime`: impulso con Delay 280 ms, mix 1, fb 0 → pico en la muestra 13 440 (±1).
  - `reverbDecays`: impulso; la energía entre 2.0 y 2.5 s es < −60 dB respecto a la del primer 0.1 s.
  - `effectsAreFinite`: cada efecto con ruido a 0 dBFS durante 1 s → todas las muestras finitas.
- [ ] **Step 2: Tests que fallan (`CharacterTests`):**
  - `everyPresetStaysWithinLatencyBudget`: para cada `PresetID`, burst tras 9600 muestras de silencio → `onsetLatency ≤ 2400` (50 ms).
  - `everyPresetIsFinite`: ruido a 0 dBFS durante 2 s → todo finito.
  - `ardillaSoundsHigher`: seno de 200 Hz → ≈ 299.7 Hz (±3 %).
  - `zeroMixIsDry`: `mix = 0` → salida igual a la entrada retrasada (error máximo < 1e−4).
- [ ] **Step 3: FAIL. Step 4: implementar. Step 5: PASS** (`swift test --filter "EffectsTests|CharacterTests"`).
- [ ] **Step 6: Commit** `feat(dsp): efectos clásicos y 12 personajes`.

---

### Task 8: VoiceProcessor — modos, fundidos, medidores y seguridad

**Files:** Create `Sources/VoicesDSP/VoiceProcessor.swift` · Test `Tests/VoicesDSPTests/VoiceProcessorTests.swift`

**Interfaces:**
- Consumes: `EnhancementChain`, `CharacterChain`, `Limiter`, `PresetID`, `ScaleKind`.
- Produces: `public enum ProcessingMode: Equatable, Sendable { case bypass, enhanced, character(PresetID) }`.
- Produces: `public final class VoiceProcessor: @unchecked Sendable`:
  - `public init(maxFrames: Int = 4096)`: preasigna la cadena de mejora, **una `CharacterChain` por preset**, el limitador y los buffers de trabajo.
  - `public func process(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int)`: in-place, hilo de audio.
  - Control, seguro desde cualquier hilo vía `Atomic`: `requestMode(_:)`, `setEnhancementLevel(_:)`, `setIntensity(_ value: Float)` (mix del personaje activo), `setScale(key:scale:)`.
  - `public var currentMode: ProcessingMode { get }`, `public var currentIntensity: Float { get }` (lectura, para la app y los tests).
  - `public func meterLevels() -> (inputDb: Float, outputDb: Float)`: pico por bloque con caída de 20 dB/s.
  - `public func takeFallbackEvent() -> Bool`: true una vez después de un fallback automático.

Comportamiento:
- `bypass`: entrada tal cual, sin mejora ni limitador.
- `enhanced`: mejora → limitador (−1 dBFS).
- `character(p)`: mejora → personaje `p` → limitador.
- Cambio de modo: fundido lineal de **20 ms (960 muestras)** entre la salida antigua y la nueva. Durante el fundido se procesan las dos rutas. La cadena de personaje entrante hace `reset()` antes de empezar. Si llega otro cambio durante un fundido, el nuevo fundido parte de la mezcla actual: la ruta saliente pasa a ser la que estaba entrando.
- Seguridad: si un bloque de salida contiene un valor no finito, el bloque se pone a cero, se hace `reset()` de todas las cadenas, el modo pasa a `enhanced` y se marca el evento de fallback.

- [ ] **Step 1: Tests que fallan:**
  - `startsEnhanced`: `VoiceProcessor().currentMode == .enhanced`.
  - `bypassIsIdentity`: en bypass, la salida es igual a la entrada.
  - `modeChangeIsSmooth`: seno de 220 Hz a −12 dBFS; cambio de enhanced a `character(.robot)` a mitad → `maxStep` en la zona del cambio ≤ 1.5 × el `maxStep` del seno de referencia en régimen.
  - `rapidModeChangesStayContinuous` (Review Focus 3): 10 cambios de modo distintos cada 100 ms sobre un seno → todo finito y `maxStep` ≤ el máximo observado en los modos estables + 0.05.
  - `loudInputNeverExceedsCeiling` (Review Focus 4): seno de 200 Hz con amplitud 4.0 en `enhanced` y en cada `character` → `peakDb ≤ -1.0`.
  - `nanTriggersFallback`: modo `character(.cueva)`; inyectar `Float.nan` en la entrada → la salida del bloque es finita, `currentMode == .enhanced`, `takeFallbackEvent() == true` y después `false`.
  - `intensityZeroMatchesEnhanced`: `character(.megafono)` con intensidad 0 → RMS a ±0.5 dB del de `enhanced`.
  - `heaviestPathIsCheap` (solo release): 60 s de audio en bloques de 128 por `character(.fantasma)` y por `character(.autotuneExtremo)` → cada uno tarda < 9 s de reloj (15 % de un núcleo). Marcar con `.enabled(if: !isDebugBuild)`.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test -c release --filter VoiceProcessorTests`).
- [ ] **Step 5: Commit** `feat(dsp): procesador de voz con modos y fallback seguro`.

---

### Task 9: ClockBridge — buffer circular con compensación de deriva

**Files:** Modify `Sources/VoicesAudio/ClockBridge.swift` · Test `Tests/VoicesAudioTests/ClockBridgeTests.swift`

**Interfaces:**
- Produces: `public final class ClockBridge: @unchecked Sendable { public init(capacity: Int = 8192, targetFill: Int = 256, tolerance: Int = 128); public func write(_ src: UnsafePointer<Float>, count: Int); public func read(into dst: UnsafeMutablePointer<Float>, count: Int); public var fill: Int { get }; public var underruns: Int { get }; public var overruns: Int { get } }`.
- Productor y consumidor únicos, sin locks, índices con `Atomic<Int>`.
- `read`: si `fill > targetFill + tolerance`, descarta una muestra en esa llamada; si `fill < targetFill − tolerance`, repite una. En underrun, rellena con ceros, cuenta el underrun y no lee hasta volver a `targetFill` (re-prebuffer). En overrun, `write` descarta lo más antiguo y cuenta el overrun.

- [ ] **Step 1: Tests que fallan:**
  - `passesSamplesInOrder`: rampa escrita y leída en bloques de 128 al mismo ritmo → idéntica, con retardo de `targetFill`.
  - `bridgeSurvivesOneHourOfDrift` (Review Focus 2): simulación sin hilos de 3600 s; el escritor produce bloques de 128 a 48 000 Hz y el lector consume bloques de 128 a 48 005 Hz (+100 ppm), intercalados por tiempo simulado. Tras el primer segundo, `underruns == 0`, `overruns == 0` y `fill` siempre dentro de `[targetFill − tolerance − 128, targetFill + tolerance + 128]`. Repetir con 47 995 Hz.
  - `underrunRefillsWithSilence`: leer sin escribir → ceros y `underruns ≥ 1`.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test --filter ClockBridgeTests`).
- [ ] **Step 5: Commit** `feat(audio): puente de reloj con compensación de deriva`.

---

### Task 10: Dispositivos, cambios y supervisor

**Files:** Create `Sources/VoicesAudio/{AudioDevice,DeviceSelection,DeviceChangeListener,EngineSupervisor}.swift` · Test `Tests/VoicesAudioTests/{DeviceSelectionTests,SupervisorTests}.swift`

**Interfaces:**
- Produces: `public struct AudioDevice: Equatable, Sendable { public let id: AudioDeviceID; public let uid: String; public let name: String; public let inputChannels: Int; public let outputChannels: Int; public let nominalSampleRate: Double }`.
- Produces: `public enum DeviceCatalog { public static func all() -> [AudioDevice]; public static func setNominalSampleRate(_ id: AudioDeviceID, _ rate: Double) throws }`. Consulta Core Audio (`kAudioHardwarePropertyDevices`, `kAudioDevicePropertyDeviceUID`, `kAudioObjectPropertyName`, configuración de streams y `kAudioDevicePropertyNominalSampleRate`).
- Produces (lógica pura): `public enum DeviceSelection { public static func isVirtualLoopback(_ d: AudioDevice) -> Bool /* nombre o UID contiene "BlackHole" */; public static func inputCandidates(_ all: [AudioDevice]) -> [AudioDevice] /* inputChannels > 0 y no loopback */; public static func outputCandidates(_ all: [AudioDevice]) -> [AudioDevice] /* outputChannels > 0 */; public static func preferredInput(_ all: [AudioDevice], savedUID: String?) -> AudioDevice? /* guardado → nombre contiene "NT-USB" → primero */; public static func preferredOutput(_ all: [AudioDevice], savedUID: String?) -> AudioDevice? /* guardado → nombre "BlackHole 2ch" → nil */ }`.
- Produces: `public final class DeviceChangeListener { public init(onChange: @escaping @Sendable () -> Void) }`. Escucha `kAudioHardwarePropertyDevices` y llama en la cola principal.
- Produces: `public enum EngineError: Error, Equatable, Sendable { case inputMissing, outputMissing, sampleRateMismatch(device: String, rate: Double), loopDetected, coreAudio(OSStatus) }` y `public enum EngineStatus: Equatable, Sendable { case stopped, running(input: String, output: String), error(EngineError) }`.
- Produces: `public enum SupervisorAction: Equatable { case start(input: AudioDevice, output: AudioDevice, monitor: AudioDevice?), stop(EngineError), none }` y `public struct EngineSupervisor { public static func decide(devices: [AudioDevice], savedInputUID: String?, savedOutputUID: String?, monitorUID: String?, current: EngineStatus) -> SupervisorAction }`. Devuelve `.start` cuando hay entrada y salida válidas y el estado actual no coincide con ellas. Devuelve `.stop(.inputMissing)` o `.stop(.outputMissing)` si falta alguno y el motor está en marcha. Devuelve `.stop(.loopDetected)` si la entrada elegida es loopback. En cualquier otro caso, `.none`.

- [ ] **Step 1: Tests que fallan** (con listas de `AudioDevice` falsas):
  - `blackHoleNeverAnInput`: `inputCandidates` excluye "BlackHole 2ch" aunque tenga entradas; incluye "RØDE NT-USB+".
  - `prefersRodeThenSaved`: sin UID guardado → RØDE; con el UID guardado de otro micro presente → ese micro; con UID guardado ausente → RØDE.
  - `prefersBlackHoleOutput`: sin guardado → "BlackHole 2ch"; si no hay BlackHole → nil.
  - `supervisorStopsWhenInputDisappears`: estado `.running` y lista sin RØDE ni otros micros → `.stop(.inputMissing)`.
  - `supervisorRestartsWhenInputReturns` (Review Focus 1): estado `.error(.inputMissing)` y lista con RØDE y BlackHole → `.start(RØDE, BlackHole, nil)`.
  - `supervisorIgnoresIrrelevantChanges`: `.running(input: "RØDE NT-USB+", output: "BlackHole 2ch")` y aparece otro dispositivo de salida → `.none`.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test --filter "DeviceSelectionTests|SupervisorTests"`).
- [ ] **Step 5: Verificación manual de `DeviceCatalog`:** test marcado `.enabled(if: ProcessInfo.processInfo.environment["VOICES_HW"] != nil)` que imprime los dispositivos. `VOICES_HW=1 swift test --filter catalogListsRealDevices` muestra "RØDE NT-USB+" (1 entrada, 48000) y "BlackHole 2ch".
- [ ] **Step 6: Commit** `feat(audio): catálogo de dispositivos y supervisor de reconexión`.

---

### Task 11: VoiceEngine — audio real entrada → BlackHole (+ monitor)

**Files:** Create `Sources/VoicesAudio/VoiceEngine.swift` · Test `Tests/VoicesAudioTests/VoiceEngineHardwareTests.swift` (solo con `VOICES_HW`)

**Interfaces:**
- Consumes: `VoiceProcessor` (Task 8), `ClockBridge` (Task 9), `AudioDevice`, `DeviceCatalog`, `EngineError`, `EngineStatus` (Task 10).
- Produces: `public final class VoiceEngine: @unchecked Sendable`:
  - `public init(processor: VoiceProcessor)`.
  - `public func start(input: AudioDevice, output: AudioDevice, monitor: AudioDevice?) throws(EngineError)`.
  - `public func stop()`.
  - `public private(set) var status: EngineStatus`.
  - `public var onStatusChange: (@Sendable (EngineStatus) -> Void)?`, llamado en la cola principal.
  - `public func measuredLatencyMs() -> Double`: suma de latencias de dispositivo y stream (`kAudioDevicePropertyLatency`, `kAudioDevicePropertySafetyOffset`, `kAudioStreamPropertyLatency`), buffers, `targetFill` y latencia del modo actual.

Diseño:
- Un AUHAL (`kAudioUnitSubType_HALOutput`) de entrada con `EnableIO` de entrada en el RØDE, formato Float32 mono a 48 kHz y buffer de **128 frames**. Su callback renderiza, llama a `processor.process` y escribe en un `ClockBridge`.
- Un AUHAL de salida en BlackHole, Float32 estéreo a 48 kHz y buffer de 128 frames. Su callback lee del bridge y duplica la señal en L y R.
- Monitor opcional: tercer AUHAL con su propio `ClockBridge`, alimentado desde el mismo callback de entrada.
- Antes de arrancar, intenta poner ambos dispositivos a 48 000 Hz con `DeviceCatalog.setNominalSampleRate`. Si no queda a 48 000, lanza `.sampleRateMismatch`.
- Si `input.uid == output.uid` o la entrada es loopback, lanza `.loopDetected`.
- Escucha `kAudioDevicePropertyDeviceIsAlive` en los tres dispositivos: si uno muere, llama a `stop()` y emite `.error(.inputMissing / .outputMissing)`.

- [ ] **Step 1: Implementar `VoiceEngine`.**
- [ ] **Step 2: Test de hardware `engineRoundTripsThroughBlackHole`** (con `VOICES_HW`): con el RØDE como entrada y BlackHole como salida, arranca el motor en bypass. Abre un AUHAL de captura sobre la entrada de BlackHole durante 3 s (BlackHole devuelve por su entrada lo que recibe por su salida). Comprueba que llega señal por encima de −90 dBFS (ruido ambiente del micro) y que el `ClockBridge` del motor tiene `underruns == 0` tras el primer segundo. Ejecutar: `VOICES_HW=1 swift test --filter engineRoundTripsThroughBlackHole`.
- [ ] **Step 3: Verificación manual.** Escribir en `README.md` la prueba siguiente y ejecutarla: QuickTime → Nueva grabación de audio → entrada "BlackHole 2ch". Hablar 10 s con el motor arrancado desde el test o desde la app (cuando exista) → se oye la voz mejorada. `measuredLatencyMs()` < 20 en `enhanced`.
- [ ] **Step 4: Commit** `feat(audio): motor en tiempo real del RØDE a BlackHole`.

---

### Task 12: Preferencias, AppModel y LaunchAgent

**Files:** Modify `Sources/VoicesKit/Preferences.swift` · Create `Sources/VoicesKit/{AppModel,LaunchAgent}.swift` · Test `Tests/VoicesKitTests/{AppModelTests,LaunchAgentTests}.swift`

**Interfaces:**
- Produces: `public struct Preferences: Codable, Equatable, Sendable { inputUID: String?; outputUID: String?; monitorUID: String?; monitorEnabled: Bool = false; enhancementLevel: Int = 1; intensities: [Int: Float] = [:] /* PresetID.rawValue → mix */; autotuneKey: Int = 0; autotuneScale: Int = 0; launchAtLogin: Bool = false; hasSeenRodeNotice: Bool = false }`. `public protocol PreferencesStore { func load() -> Preferences; func save(_ p: Preferences) }`, más `UserDefaultsPreferencesStore` (clave `"preferences.v1"`, JSON) y `InMemoryPreferencesStore` para tests. **No incluye el modo activo.**
- Produces: `@MainActor @Observable public final class AppModel`:
  - `public init(store: PreferencesStore, processor: VoiceProcessor)`.
  - `public private(set) var mode: ProcessingMode` (siempre `.enhanced` al iniciar).
  - `public var preferences: Preferences` (cada cambio guarda y empuja los valores al procesador).
  - `public var engineStatus: EngineStatus`.
  - `public var levels: (inputDb: Float, outputDb: Float)`.
  - `public func select(_ mode: ProcessingMode)`, `public func panic()` (= `select(.bypass)`), `public func intensity(for p: PresetID) -> Float` (por defecto 1), `public func setIntensity(_ v: Float, for p: PresetID)`.
  - `public func applyFallbackIfNeeded() -> Bool`: lee `takeFallbackEvent` y sincroniza `mode`.
  - `public var showRodeNotice: Bool { !preferences.hasSeenRodeNotice }`.
- Produces: `public enum LaunchAgent { public static let label = "local.thevoices.agent"; public static func plist(executablePath: String, runAtLoad: Bool) -> [String: Any]; public static var plistURL: URL /* ~/Library/LaunchAgents/local.thevoices.agent.plist */; public static func install(executablePath: String, runAtLoad: Bool) throws; public static func isRunningUnderLaunchd: Bool /* env XPC_SERVICE_NAME == label */; public static func kickstart() throws }`. `install` escribe el plist y ejecuta `launchctl bootout` (ignorando el error) y `launchctl bootstrap gui/<uid> <plist>`. `kickstart` ejecuta `launchctl kickstart gui/<uid>/<label>`.

- [ ] **Step 1: Tests que fallan:**
  - `alwaysStartsEnhanced`: un store con preferencias guardadas cualesquiera → `AppModel.mode == .enhanced` y `processor.currentMode == .enhanced`.
  - `selectingCharacterUsesSavedIntensity`: intensidad 0.4 guardada para `.robot`; `select(.character(.robot))` → `processor.currentIntensity == 0.4`.
  - `panicIsBypass`: `panic()` → `mode == .bypass`.
  - `preferencesPersistButModeDoesNot`: cambiar el nivel a Radio y seleccionar un personaje; crear un nuevo `AppModel` con el mismo store → nivel Radio y `mode == .enhanced`.
  - `plistRelaunchesOnlyOnCrash`: `plist(executablePath: "/x", runAtLoad: true)` tiene `Label == label`, `ProgramArguments == ["/x"]`, `RunAtLoad == true`, `KeepAlive == ["SuccessfulExit": false]` y `ThrottleInterval == 5`.
- [ ] **Step 2: FAIL. Step 3: implementar. Step 4: PASS** (`swift test --filter "AppModelTests|LaunchAgentTests"`).
- [ ] **Step 5: Commit** `feat(kit): estado de la app, preferencias y agente de launchd`.

---

### Task 13: Interfaz — barra de menús, ajustes, notificaciones y atajos

**Files:** Create/Modify `Sources/TheVoices/{TheVoicesApp,MenuContentView,SettingsView,Hotkeys,Notifier}.swift` · Create `Sources/VoicesKit/StatusIcon.swift` · Test `Tests/VoicesKitTests/StatusIconTests.swift`

**Interfaces:**
- Consumes: `AppModel`, `Preferences`, `LaunchAgent` (Task 12); `VoiceEngine`, `DeviceCatalog`, `DeviceChangeListener`, `EngineSupervisor` (Tasks 10–11); `PresetID`, `EnhancementLevel`, `ScaleKind` (DSP).
- Produces (en `VoicesKit`): `public enum StatusIcon { public static func symbol(mode: ProcessingMode, status: EngineStatus) -> String }`: error → `exclamationmark.triangle.fill`; bypass → `mic`; personaje → `theatermasks.fill`; mejorada → `waveform`.
- Produces: `extension KeyboardShortcuts.Name`: `.enhanced` (⌃⌥0), `.panic` (⌃⌥B) y `static func preset(_ p: PresetID) -> Self` con nombre `"preset.\(p.rawValue)"`. Los nueve primeros presets tienen por defecto ⌃⌥1…⌃⌥9; los tres restantes no tienen atajo por defecto.

Comportamiento:
- **Arranque (`TheVoicesApp.init` o delegado):** si `LaunchAgent` está instalado y la app no corre bajo launchd → `kickstart()` y salir con código 0. Si no está instalado → `install(runAtLoad: preferences.launchAtLogin)` usando `Bundle.main.executablePath` y seguir. Después, pedir permiso de micrófono (`AVCaptureDevice.requestAccess(for: .audio)`). Si se deniega, estado de error con un texto que explica cómo activarlo en Ajustes del Sistema.
- **Supervisión:** `DeviceChangeListener` y el arranque llaman a `EngineSupervisor.decide` y aplican la acción sobre `VoiceEngine`. Un temporizador de 30 Hz en el hilo principal actualiza `levels` y llama a `applyFallbackIfNeeded()`.
- **Menú (`MenuContentView`), de arriba abajo:**
  1. Estado ("Activo: RØDE NT-USB+ → BlackHole 2ch" o el error en rojo).
  2. Dos medidores (entrada y salida).
  3. Interruptor "Procesado activo" (apagado = bypass).
  4. "Mi voz mejorada" con selector Suave/Normal/Radio.
  5. Sección "Personajes": una fila por preset con marca en el activo; al pulsar el activo, vuelve a voz mejorada. Para el activo, deslizador "Intensidad".
  6. "Escucharme en auriculares" (interruptor).
  7. "Ajustes…" y "Salir de The Voices".
- **Ajustes (`SettingsView`, escena `Settings`):**
  - Selectores de micrófono, salida y auriculares de monitor, desde `inputCandidates` y `outputCandidates`.
  - Tonalidad (Do…Si) y escala del autotune.
  - Grabadores `KeyboardShortcuts.Recorder` para voz mejorada, pánico y cada preset.
  - "Abrir al iniciar sesión", que reinstala `LaunchAgent` con el nuevo `runAtLoad`.
  - Texto con la latencia medida.
- **Aviso del RØDE:** la primera vez (`showRodeNotice`), una alerta: "Para el mejor resultado, apaga el procesado APHEX del NT-USB+ en RØDE Central (Compellor, Aural Exciter, Big Bottom, puerta de ruido y filtro de graves). The Voices ya hace ese trabajo." Botón "Entendido", que guarda `hasSeenRodeNotice = true`.
- **Notificaciones (`Notifier`, UserNotifications):** al pasar a `.error`, "The Voices: no llega tu voz" con el motivo. Al volver a `.running` tras un error, "The Voices: voz recuperada". Tras un fallback, "Un efecto falló; vuelves a tu voz mejorada".
- **Salir:** `exit(0)` (código 0, para que launchd no la relance).

- [ ] **Step 1: Test que falla `StatusIconTests`:** cada combinación devuelve el símbolo indicado; el error tiene prioridad.
- [ ] **Step 2: FAIL. Step 3: implementar `StatusIcon`. Step 4: PASS.**
- [ ] **Step 5: Implementar el resto de la interfaz, los atajos, las notificaciones y el arranque.**
- [ ] **Step 6: Verificación manual** con `./scripts/install.sh && open ~/Applications/"The Voices.app"`:
  - Aparece el aviso del RØDE una vez.
  - El icono es la onda.
  - En QuickTime con entrada BlackHole se oye la voz mejorada.
  - ⌃⌥1 → ardilla con Zoom (o QuickTime) en primer plano.
  - ⌃⌥B → voz cruda.
  - ⌃⌥0 → mejorada.
  - Desenchufar el RØDE → icono de error y notificación; reenchufar → vuelve solo.
  - `kill -9` del proceso → launchd la relanza en ≤ 10 s, en voz mejorada.
  - "Salir" → no se relanza.
- [ ] **Step 7: Commit** `feat(app): barra de menús, ajustes, atajos y notificaciones`.

---

### Task 14: README y verificación final del spec

**Files:** Modify `README.md`

- [ ] **Step 1: Completar el README:** instalación (BlackHole, `scripts/install.sh`), cómo elegir "BlackHole 2ch" en Zoom, Meet, Teams, FaceTime, GarageBand y Audacity, cómo apagar APHEX en RØDE Central, la lista de atajos, la limitación conocida (si la app no corre, BlackHole queda en silencio; se relanza sola si falla) y la nota de que, con firma ad-hoc, macOS puede volver a pedir el permiso de micrófono tras recompilar.
- [ ] **Step 2: Ejecutar `swift test` y `swift test -c release`** → todo en verde.
- [ ] **Step 3: Recorrer el §12 del spec** (5 comprobaciones) en una llamada de prueba de Zoom o FaceTime. Medir el retardo grabando un chasquido por las dos rutas en Audacity (RØDE directo y BlackHole) → ≤ 20 ms en mejorada y ≤ 50 ms con personaje. CPU en el Monitor de Actividad < 15 % con Fantasma activo durante 5 min.
- [ ] **Step 4: Antes de cualquier push:** revisar autoría con `git log --format='%an %ae%n%B'` (solo "Benjamin Fernandez Carrasco") y que ningún fichero mencione herramientas de IA.
- [ ] **Step 5: Commit** `docs: guía de uso y verificación`.
