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

## Instalador (.pkg)

```sh
./scripts/build-pkg.sh   # genera "build/The Voices-<versión>.pkg"
```

El instalador copia `The Voices.app` a `/Applications` (con pantallas de bienvenida, licencia y final). La app está firmada solo de forma ad-hoc y el `.pkg` no está firmado: si lo copias a otro Mac, macOS lo bloqueará la primera vez y habrá que abrirlo con clic derecho → Abrir (o permitirlo en Ajustes del Sistema → Privacidad y seguridad). BlackHole 2ch no va incluido: instálalo con `brew install blackhole-2ch`.

## Licencia

Se puede usar y mejorar, siempre mencionando al creador original, **Benjamin Fernandez Carrasco**, y creando los forks a partir del repositorio original. Texto completo en [LICENSE](LICENSE).

**Repositorio Original:** https://github.com/benjifc/the-voices (creador: Benjamin Fernandez Carrasco). Los forks y las mejoras deben partir de ese repositorio.

Tests: `swift test` (los de rendimiento: `swift test -c release`).
