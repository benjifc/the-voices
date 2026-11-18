# Registro de cambios

Todos los cambios relevantes de The Voices se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y las versiones siguen [Versionado Semántico](https://semver.org/lang/es/) (`MAJOR.MINOR.PATCH`).

## [Sin publicar]

### Añadido

- Procesado de voz en tiempo real (48 kHz, mono): filtros biquad, puerta de ruido, compresor, de-esser y limitador de pico con lookahead.
- Cadena «Mi voz mejorada» con tres niveles (Suave, Normal y Radio).
- Cambio de tono granular (`PitchShifter`) y detector de tono YIN (`PitchDetector`).
- Instalador `.pkg` (`scripts/build-pkg.sh`) que instala la app en `/Applications`.
- Actualizaciones automáticas con Sparkle: la app busca nuevas versiones en las releases de GitHub, comprueba su firma y se actualiza sola.
- Licencia de uso y mejora con atribución al creador original.
