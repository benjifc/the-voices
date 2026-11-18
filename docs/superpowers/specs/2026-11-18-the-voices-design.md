# The Voices — Diseño (Fase 1: efectos clásicos)

Fecha: 2026-11-18
Autor: Benjamin Fernandez Carrasco

## 1. Intención y porqué

App personal para el Mac mini (M4, 16 GB, macOS 27) que procesa en tiempo real la voz
del micrófono RØDE NT-USB+ y la entrega como micrófono a cualquier otra app (Zoom,
Meet, Teams, FaceTime, Slack, GarageBand, Audacity…).

Es para **pasarlo bien**:

- **Reuniones de trabajo**: sonar mejor por defecto y, de vez en cuando, activar una
  voz de personaje para hacer reír. Cambiar de voz tiene que ser rápido y discreto,
  sin buscar ventanas en mitad de la llamada.
- **Podcast en ratos libres**: grabar con la voz pulida y dar voz a personajes.

Las voces de personaje son **originales** (robot, ardilla, monstruo, etc.), no
imitaciones de actores o personas reales.

## 2. Fases (solo la Fase 1 se planifica ahora)

| Fase | Contenido |
|------|-----------|
| **1 (este documento)** | App nativa + BlackHole como micrófono virtual + cadena de mejora de voz + voces de personaje con efectos clásicos + autotune |
| 2 | Micrófono virtual propio ("The Voices Mic") que sustituye a BlackHole |
| 3 | Conversión de voz con IA (tipo RVC, vía Core ML) para personajes "premium" |

La arquitectura de la Fase 1 debe permitir las fases 2 y 3 sin reescribir: el destino
de salida y los "motores" de voz son piezas intercambiables.

## 3. Objetivos

1. Tu voz procesada llega a cualquier app eligiendo **"BlackHole 2ch"** como micrófono.
2. **Modo "Mi voz mejorada"** activo por defecto: filtro de graves, puerta de ruido,
   ecualización, compresor, de-esser y limitador.
3. **Voces de personaje** con efectos clásicos, cambiables al vuelo.
4. **Autotune** (corrección de tono a una escala), suave o exagerado.
5. Control desde la **barra de menús** y con **atajos de teclado globales** que funcionan
   aunque Zoom esté en primer plano.
6. **Tecla de pánico**: pasa al instante a tu voz **sin procesar** (bypass total) y se
   queda así hasta que elijas otro modo. *(Decisión mía: fijo, no configurable; para
   volver a la voz mejorada hay un atajo propio.)*

## 4. No-objetivos (Fase 1)

- Conversión de voz con IA (Fase 3).
- Micrófono virtual propio / driver de audio (Fase 2).
- Grabación integrada en la app: para el podcast se graba desde GarageBand/Audacity/etc.
  eligiendo BlackHole como entrada. *(Decisión mía: mantiene la Fase 1 pequeña; es fácil
  de añadir después.)*
- Distribución en App Store, firma de Apple Developer, notarización, otros usuarios.
- Imitar voces de personas reales.

## 5. Anti-objetivos (fracaso aunque "funcione")

- **Dejarte mudo en una reunión**: si algo falla (efecto, dispositivo desconectado,
  error de audio), la app tiene que volver a tu voz o avisarte de forma visible.
- **Retardo perceptible** en el modo de voz mejorada (en una llamada se nota el desfase).
- **Chasquidos, cortes o robotización** no buscados en la voz mejorada.
- **Cambios de voz con "pop"**: al cambiar de preset no debe oírse un golpe.
- Ocupar mucha CPU y que el Mac vaya lento durante una videollamada.

## 6. Restricciones y hechos del entorno

- Hardware: Mac mini M4, 16 GB, macOS 27.0.1. Xcode 27.2, Swift 6.4.
- Micrófono: RØDE NT-USB+, 1 canal de entrada, 48 kHz, dispositivo de entrada por defecto.
- **BlackHole 2ch ya está instalado** (Homebrew, `blackhole-2ch`).
- El NT-USB+ tiene **procesado interno propio** (APHEX: Compellor, Aural Exciter,
  Big Bottom, puerta de ruido, filtro de graves) configurable con RØDE Central/Connect.
  *(Decisión mía)* La cadena de mejora de la app se ajusta para usarse con ese procesado
  **apagado**: el README explica cómo apagarlo en RØDE Central y la app muestra un aviso
  la primera vez. No habrá un segundo juego de ajustes para "procesado RØDE activo".
- Uso personal: compilación local con firma ad-hoc o con la cuenta de desarrollador
  gratuita; sin App Store.
- Hay que pedir el permiso de micrófono de macOS.
- Para no oír eco ni crear bucles: la app **nunca** debe usar BlackHole como entrada.

## 7. Enfoques considerados

| Enfoque | Ventajas | Inconvenientes |
|---------|----------|----------------|
| 1. App Swift + micrófono virtual propio | Una sola pieza, nombre propio en Zoom, máxima calidad | El driver es lo más laborioso y arriesgado |
| **2. App Swift + BlackHole** ✅ | Funciona pronto y con poco riesgo; BlackHole ya instalado | Dos piezas; en Zoom aparece como "BlackHole 2ch" |
| 3. Prototipo Python + BlackHole | Lo más rápido; la IA de la Fase 3 es nativa en Python | Más retardo, peor experiencia en directo, habría que rehacerlo |

**Elegido: 2**, como paso hacia la 1. El destino de salida se encapsula para que en la
Fase 2 se cambie BlackHole por el micrófono propio sin tocar el resto. La 3 se
descartó porque obliga a tirar el trabajo para tener una app de verdad.

## 8. Lo decidido sobre el cómo

- **App nativa macOS en Swift / SwiftUI**, que vive en la **barra de menús**.
- **Salida a BlackHole 2ch**; entrada desde el RØDE NT-USB+.
- Primero los **efectos clásicos**; la IA queda para la Fase 3.

## 9. Comportamiento

### 9.1 Flujo de audio

```
RØDE NT-USB+ (48 kHz, mono)
   → Mejora de voz (siempre activa salvo bypass)
   → Voz de personaje / Autotune (opcional, uno a la vez)
   → Limitador final (protege de picos)
   → BlackHole 2ch (estéreo: misma señal en L y R)
   → [opcional] Monitor en auriculares
```

### 9.2 Mejora de voz ("Mi voz mejorada")

Cadena fija con un único control principal de intensidad (Suave / Normal / Radio) y
ajustes avanzados plegados:

1. Filtro de graves (~80 Hz) para quitar golpes y zumbidos.
2. Puerta / expansor de ruido suave (que no corte el final de las palabras).
3. Ecualizador: un poco de cuerpo en graves, claridad en medios-agudos y presencia.
4. Compresor para igualar el volumen.
5. De-esser para suavizar las "eses".
6. Limitador para que nunca sature.

### 9.3 Voces de personaje (propuesta inicial; los nombres son míos y se pueden cambiar)

| Preset | Idea del sonido |
|--------|-----------------|
| Ardilla | Tono +7 semitonos, formantes arriba |
| Gigante | Tono −5, formantes abajo, algo de cuerpo |
| Monstruo | Tono −8, formantes abajo, distorsión ligera |
| Robot | Modulación en anillo + bitcrusher suave |
| Alien | Tono oscilante + flanger |
| Radio antigua | Paso banda + saturación + ruido leve |
| Teléfono | Paso banda estrecho |
| Megáfono | Paso banda + distorsión |
| Cueva / Eco | Delay + reverb grande |
| Fantasma | Reverb larga + tono ligeramente desafinado |
| Autotune suave | Corrección de tono discreta a la escala elegida |
| Autotune extremo | Corrección instantánea (efecto robótico de música pop) |

- Los personajes se aplican **encima** de la voz mejorada.
- El autotune permite elegir tonalidad y escala (mayor/menor/cromática).
- Cada preset tiene un único deslizador de "intensidad"/mezcla.

### 9.4 Interfaz

- **Icono en la barra de menús** que cambia según el estado (normal, personaje activo,
  bypass, error).
- Menú desplegable con:
  - Interruptor general (activado / bypass).
  - "Mi voz mejorada" con su nivel.
  - Lista de personajes (uno activo como máximo, o ninguno).
  - Medidor de nivel de entrada y de salida.
  - Monitorizar en auriculares (activado / desactivado).
  - Abrir ajustes.
- **Ventana de ajustes**: dispositivo de entrada y salida, ajustes avanzados de la
  mejora, tonalidad del autotune y atajos de teclado.
- **Atajos globales** (por defecto, configurables): uno por personaje, otro para volver
  a "voz mejorada" y la **tecla de pánico** (bypass total).
- Arranque opcional al iniciar sesión.
- Recuerda los ajustes entre sesiones (dispositivos, nivel de mejora, tonalidad, atajos),
  pero **siempre arranca en "Mi voz mejorada" sin personaje ni bypass**. *(Decisión mía:
  así nunca entras en una reunión de trabajo sonando como la ardilla.)*

### 9.5 Monitorización

- Opción para escucharte procesado por los auriculares (dispositivo de salida elegible).
  Viene **desactivada por defecto** porque escucharte con retardo resulta incómodo. Si
  quieres oírte sin retardo, puedes usar la salida de auriculares del propio RØDE (se oye
  la voz sin procesar).

### 9.6 Robustez

- Si se desconecta el RØDE o BlackHole, la app lo muestra en el icono y se reconecta sola
  cuando el dispositivo vuelve.
- Si la frecuencia de muestreo de entrada y la de salida no coinciden, la app lo resuelve
  (conversión o aviso claro), nunca con silencio.
- Los cambios de preset se hacen con un fundido corto (sin "pop").
- Si un efecto falla, se pasa automáticamente a la voz mejorada.
- **Si la app se cierra o falla, BlackHole se queda en silencio** y nada puede devolver la
  voz cruda a Zoom. Es una limitación conocida de la Fase 1 que se resuelve de verdad en
  la Fase 2, con el micrófono propio. *(Decisión mía)* Como mitigación barata, un agente
  de `launchd` con KeepAlive relanza la app automáticamente si se cae, y la app vuelve a
  arrancar en voz mejorada.

## 10. Objetivos medibles

- Retardo añadido por la app (entrada → BlackHole):
  - Voz mejorada: **≤ 20 ms**.
  - Personajes y autotune: **≤ 50 ms**.
- CPU de la app durante el uso normal: **< 15 %** de un núcleo en el M4.
- 1 hora de llamada sin cortes ni chasquidos.
- Cambio de preset audible en < 100 ms desde que se pulsa el atajo.

## 11. Lo que queda a criterio de quien lo construya

- Motor de audio: AVAudioEngine, Core Audio (AUHAL) directo o una mezcla de ambos.
  Ojo: el RØDE y BlackHole tienen relojes distintos, así que hace falta compensar la
  deriva (buffer circular con corrección, conversión de frecuencia o dispositivo
  agregado).
- DSP de cambio de tono y formantes con baja latencia: implementación propia
  (PSOLA/granular) o una librería con licencia compatible (p. ej., Signalsmith Stretch,
  MIT). Evitar `AVAudioUnitTimePitch` si su latencia supera el objetivo.
- Detección de tono para el autotune (p. ej., YIN).
- Mecanismo de atajos globales.
- Estructura del proyecto, tests y valores exactos de cada preset.
- Formato de guardado de preferencias.

## 12. Cómo se comprueba que funciona

1. Elegir "BlackHole 2ch" como micrófono en Zoom (o QuickTime → Nueva grabación de
   audio) y comprobar que se oye la voz procesada.
2. Cambiar de personaje con atajos mientras Zoom está en primer plano.
3. Pulsar la tecla de pánico y comprobar que vuelve la voz al instante.
4. Desenchufar y reenchufar el RØDE durante una llamada de prueba.
5. Medir el retardo (p. ej., grabando un chasquido por las dos rutas) y la CPU con el
   Monitor de Actividad.
