# Registro de cambios

Todos los cambios relevantes de The Voices se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen [Versionado Semántico](https://semver.org/lang/es/) (`MAJOR.MINOR.PATCH`).

## [Sin publicar]

## [0.1.0] - 2026-11-18

### Añadido

- Primera versión de desarrollo: por ahora la app solo muestra el icono de la barra de menús (con «Buscar actualizaciones…» y «Salir»); el motor de audio todavía no está conectado a la interfaz.
- Biblioteca de procesado de voz (48 kHz, mono): filtros biquad, puerta de ruido, compresor, de-esser y limitador de pico con lookahead.
- Cadena «Mi voz mejorada» con tres niveles (Suave, Normal y Radio).
- Cambio de tono granular (`PitchShifter`) y detector de tono YIN (`PitchDetector`).
- Instalador `.pkg` (`scripts/build-pkg.sh`) que instala la app en `/Applications`.
- Actualizaciones automáticas con Sparkle: la app busca nuevas versiones en las releases de GitHub, comprueba su firma y se actualiza sola.
- Licencia de uso y mejora con atribución al creador original.

[Sin publicar]: https://github.com/benjifc/the-voices/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/benjifc/the-voices/releases/tag/v0.1.0
