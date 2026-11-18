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
./scripts/build-pkg.sh   # genera "build/TheVoices-<versión>.pkg"
```

El instalador copia `The Voices.app` a `/Applications` (con pantallas de bienvenida, licencia y final). La app está firmada solo de forma ad-hoc y el `.pkg` no está firmado: si lo copias a otro Mac, macOS lo bloqueará la primera vez y habrá que abrirlo con clic derecho → Abrir (o permitirlo en Ajustes del Sistema → Privacidad y seguridad). BlackHole 2ch no va incluido: instálalo con `brew install blackhole-2ch`.

## Versiones y actualizaciones

- Las versiones siguen [SemVer](https://semver.org/lang/es/) (`X.Y.Z`); cada una tiene su etiqueta `vX.Y.Z` y su release en [GitHub](https://github.com/benjifc/the-voices/releases), con el instalador `TheVoices-X.Y.Z.pkg` y `TheVoices-X.Y.Z.zip`. Los cambios de cada versión están en [CHANGELOG.md](CHANGELOG.md).
- **La app se actualiza sola** (Sparkle): busca versiones nuevas al arrancar y cada 6 horas, descarga la actualización en segundo plano, comprueba su firma EdDSA y la instala. También hay «Buscar actualizaciones…» en el menú. La clave pública de firma va en `Support/Info.plist` (`SUPublicEDKey`); la privada está en el llavero de quien publica.
- El `.pkg` deja la app a nombre del usuario que instala para que las actualizaciones no pidan contraseña.

### Publicar una versión

1. Anota los cambios bajo `## [Sin publicar]` en `CHANGELOG.md`.
2. Desde `main` y con el árbol limpio: `./scripts/release.sh X.Y.Z --dry-run` para probar (genera todo en `build/` sin tocar git ni GitHub).
3. `./scripts/release.sh X.Y.Z` publica: pasa los tests, sube la versión, firma el `.zip`, genera `appcast.xml`, commitea, etiqueta, hace push y crea la release (pide confirmación; `--draft` la deja como borrador).

Hace falta la clave privada de Sparkle en el llavero (`.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` muestra la pública). **Haz copia de seguridad de la clave** (`generate_keys -x fichero`): sin ella no se pueden publicar actualizaciones que las apps ya instaladas acepten.

## Licencia

Se puede usar y mejorar, siempre mencionando al creador original, **Benjamin Fernandez Carrasco**, y creando los forks a partir del repositorio original. Texto completo en [LICENSE](LICENSE).

**Repositorio Original:** https://github.com/benjifc/the-voices (creador: Benjamin Fernandez Carrasco). Los forks y las mejoras deben partir de ese repositorio.

Tests: `swift test` (los de rendimiento: `swift test -c release`).
