# The Voices

App de barra de menús para macOS que procesa en tiempo real la voz de un micrófono USB y la envía al dispositivo virtual BlackHole, para usarla como micrófono en otras aplicaciones.

## Requisitos

- macOS 15 o superior
- BlackHole 2ch: `brew install blackhole-2ch`
- Xcode / Swift 6

## Compilar e instalar

```sh
./scripts/build-app.sh   # genera build/The Voices.app
./scripts/install.sh     # compila y copia a ~/Applications
```

Tests: `swift test` (los de rendimiento: `swift test -c release`).
