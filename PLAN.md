# iOS Dash Clipboard — plan de construcción

Fecha: 22 de septiembre de 2026. Estado: plan preparado antes de delegar la implementación.

## Actualización de producto — guardado explícito desde clipboard

Tras un ensayo breve sin ese flujo, el usuario restauró el guardado explícito desde el clipboard en la app y el teclado. Ambos muestran un botón azul de cápsula, **Save from clipboard**. `UIPasteControl` no permite cambiar su título visible, por lo que el botón usa `UIButton.Configuration.filled()` o SwiftUI `.borderedProminent` y lee `UIPasteboard` sólo al tocarlo, aceptando la autorización nativa que presente iOS. Tocar un snippet guardado sigue insertándolo directamente mediante `textDocumentProxy.insertText(_:)`; guardar nunca inserta en el campo activo. Full Access habilita guardar, favorito y eliminación desde el teclado.

## Objetivo y alcance

Aplicación nativa Swift cuyo producto principal es un Custom Keyboard Extension: copiar texto → abrir el teclado → guardar explícitamente → tocar el snippet para insertarlo mediante `textDocumentProxy.insertText()`.

Repositorio local: `/Users/kevin/Documents/Github/ios-dash-clipboard`. Nombre del producto: **iOS Dash Clipboard**. Dos targets de producto (app y keyboard), más targets de tests cuando sean necesarios. Sin IA, backend, cuentas, analytics, anuncios, servicios de red, sincronización cloud ni frameworks externos de UI. No publicar un repositorio remoto ni distribuir la app como parte de este trabajo.

La implementación la realizará un agente **gpt-5.6-terra**, una vez terminado este plan. El agente principal se ocupa del plan, la revisión y la coordinación; no escribe la aplicación.

## Decisiones iniciales

- Swift, SwiftUI en la app; `UIInputViewController` y UIKit donde lo necesite el teclado. SwiftUI incrustado mediante `UIHostingController` solo si no complica el teclado.
- Deployment target iOS/iPadOS 17.0. Entorno comprobado: Xcode 26.3, SDK iOS 26.2 y runtime de simulador iOS 26.3. Componentes nativos adoptan el aspecto del sistema, incluido Liquid Glass en iOS 26; en iOS 17–18 conservan su apariencia nativa. No emular vidrio ni utilizar APIs exclusivas de iOS 26 sin disponibilidad.
- App Group configurable y coincidente en ambos entitlements. Identificadores iniciales de desarrollo documentados; firma de dispositivo requiere el equipo y perfiles del usuario. Compilar para simulador sin requerir credenciales.
- Modelo `ClipboardItem`: UUID, texto completo, fecha de creación y favorito. Recientes por fecha descendente con desempate determinista. Favoritos filtra ese orden. No reordenación manual porque contradice el orden cronológico y no aporta al flujo inicial.
- Un store compartido pequeño basado en SwiftData dentro del App Group, con CloudKit desactivado. Cada mutación coordina lectura-modificación-guardado entre procesos para no perder cambios entre app y extensión. El JSON anterior sólo sirve como entrada de migración; no guardar snippets en UserDefaults.
- No eliminar espacios, saltos ni Unicode del texto guardado. Rechazar entradas vacías/sin contenido útil sin modificar el original. Guardar repetidamente el mismo texto consecutivo no crea otro UUID ni pierde favoritos. Política exacta y tests antes de implementar deduplicación.
- Errores de contenedor, escritura o decodificación se muestran y no se convierten silenciosamente en un almacén vacío. Nunca sobrescribir un archivo corrupto con una lista vacía.
- Compartir archivos fuente entre targets; no añadir capas de arquitectura, bases de datos o dependencias sin una necesidad demostrada.

## Restricciones de Apple y comprobación temprana

La documentación actual de open access permite lectura del contenedor compartido sin Full Access y exige ese acceso ampliado para escribir. La guía archivada describe restricciones más antiguas: priorizar documentación actual y validar en el runtime disponible.

- `RequestsOpenAccess = true` permite al usuario habilitar Full Access; no equivale a que esté concedido. Consultar `hasFullAccess` desde el teclado, también al reaparecer.
- Sin Full Access: permitir leer e insertar snippets existentes cuando el contenedor esté disponible; deshabilitar las mutaciones desde el teclado con una explicación breve. Si no hay acceso real al contenedor, mostrar estado recuperable y conservar el cambio de teclado.
- Full Access habilita guardar, favoritos y eliminar desde la extensión. El acceso al pasteboard también se comprobará como restricción del teclado. El permiso habilita capacidades de red del sistema, pero esta app no implementa comunicaciones de red.
- `UIPasteControl` (iOS 16+) es la primera opción de pegado explícito, con receptor `UIPasteConfigurationSupporting` y carga textual mediante proveedores. Guardar lo recibido; nunca simular pulsaciones ni leer automáticamente el clipboard al abrir el teclado.
- La disponibilidad de `UIPasteControl` en UIKit no demuestra por sí sola que funcione dentro de una extensión: comprobar headers del SDK, compilar y probar dentro del keyboard real. Documentar comportamiento con y sin Full Access.
- Si el control nativo no sirve en ese contexto, usar únicamente una lectura explícita oficial de `UIPasteboard` tras pulsar Guardar, aceptando la autorización que presente iOS. Si tampoco es viable, guardar desde la app contenedora con control de pegado nativo y explicar la limitación. No afirmar que el flujo ideal está validado sin haberlo probado.
- El botón de cambio de teclado sigue `needsInputModeSwitchKey`. Usar `handleInputModeList(from:with:)` con todos los eventos táctiles para la lista y pulsación prolongada; `advanceToNextInputMode()` solo donde corresponda. No duplicar innecesariamente el globo que iOS presenta fuera de la vista.
- No leer el contexto del documento ni monitorizar clipboard en segundo plano. No registrar contenido de snippets en logs.
- iOS sustituye los teclados de terceros en campos seguros y algunos campos telefónicos, y las apps pueden rechazarlos. Documentarlo como restricción, sin hacks.

## Estructura propuesta

```
iOSDashClipboard.xcodeproj/
ClipboardApp/
  App/
  Views/
  Services/
ClipboardKeyboard/
  KeyboardViewController.swift
  KeyboardView.swift
  Components/
Shared/
  Models/ClipboardItem.swift
  Storage/ClipboardStore.swift
  Constants/AppGroup.swift
Tests/
UITests/                     # solo pruebas de integración útiles
docs/
  APPLE_APIS.md
  VALIDATION.md
README.md
```

## Fases y criterios de aceptación

### 1. Proyecto y flujo crítico

Crear el proyecto Xcode reproducible, targets, scheme compartido, embedding de la extensión, entitlements y almacenamiento. Construir una pantalla mínima para crear un snippet y un teclado mínimo para mostrarlo e insertarlo.

**Puerta de calidad:** compilan app y extensión; una escritura desde la app se lee desde el teclado; un toque llama a `textDocumentProxy.insertText(item.text)` directamente y conserva el texto completo. Validar inserción real en un campo cuando el entorno permita activar la extensión. Un mock no sustituye esta validación.

### 2. Almacenamiento robusto y sincronización

Lecturas y mutaciones coordinadas entre procesos, escrituras atómicas y recuperación explícita de errores. Actualizar la UI local al confirmar escritura. Recargar al aparecer y al volver al foreground; usar una notificación interproceso oficial sin payload sensible para refrescar el proceso visible, con recarga de lifecycle como respaldo. Un lector sin Full Access no debe intentar crear carpetas, archivos de bloqueo ni migraciones.

**Puerta de calidad:** cierre/reapertura conserva el estado; dos instancias del store no pierden actualizaciones; corrupción y contenedor inaccesible no destruyen datos; operaciones de disco no bloquean perceptiblemente el teclado.

### 3. Teclado completo y guardar clipboard

Añadir Recientes/Favoritos, acción explícita nativa para guardar, favoritos, eliminar mediante menú contextual o acciones nativas, feedback accesible y globo del sistema. Mantener una lista compacta con carga eficiente, alturas adaptables, truncado visual y texto completo al insertar. No QWERTY ni edición de texto propia dentro del teclado.

**Puerta de calidad:** guardar actualiza la lista inmediatamente tras persistir; repetir guardado no duplica; favorito y eliminación persisten; los fallos se muestran sin falso éxito; estados sin Full Access, clipboard vacío/no textual/no disponible y permiso denegado no bloquean la navegación. Guardado y pegado se prueban dentro de la extensión real, no solo en un host de prueba.

### 4. Aplicación contenedora

`NavigationStack`, `List`, búsqueda, filtro de favoritos, creación, edición con `TextEditor`, eliminación, `swipeActions`, `contextMenu`, sheets y toolbars nativas. Guardado de clipboard mediante control nativo. Settings con privacidad, instrucciones de activación y acceso oficial a Settings donde sea válido. Editor con guardar/cancelar y gestión clara de errores; no perder cambios si falla persistencia.

**Puerta de calidad:** crear/editar/buscar/favoritos/eliminar/importar funcionan y reflejan cambios en el teclado. Sin dashboard ni controles custom innecesarios.

### 5. Onboarding, accesibilidad y privacidad

Onboarding breve en primer lanzamiento: finalidad, Settings → General → Keyboard → Keyboards → Add New Keyboard, uso del globo y funciones que requieren Full Access. Texto de privacidad: “Your clipboard stays on your device.” Explicar que no se envían datos, sin negar las capacidades generales que el permiso concede al sistema. Instrucciones consultables después desde Settings.

Labels de VoiceOver, Dynamic Type, colores semánticos, Dark/Light, Reduce Motion y Reduce Transparency. Evitar feedback háptico obligatorio y comprobar disponibilidad en extensión. Excluir archivos de snippets de backup si es necesario para cumplir literalmente permanencia local; documentar la consecuencia de perderlos al desinstalar o cambiar de dispositivo. Revisar manifest de privacidad y required-reason APIs realmente usadas.

### 6. Tests y verificación final

Escribir tests de lógica junto a la implementación y completar esta fase al final. XCTest o Swift Testing, sin pruebas triviales para inflar cobertura.

Tests mínimos significativos:

- Persistencia y reapertura, orden determinista, filtro de favoritos y favorito tras recargar.
- Crear, editar y eliminar sin perder texto Unicode, emojis, saltos, URLs ni emails.
- Deduplicación consecutiva, distinción de textos diferentes y conservación de identidad/favorito.
- Dos stores con actualizaciones intercaladas/concurrentes, sin pérdida de cambios.
- Contenedor ausente, archivo corrupto, fallos de escritura y modo de solo lectura.
- Texto muy largo y volumen amplio de snippets, sin truncado destructivo.
- Integración útil para inserción y política de permisos cuando pueda aislarse sin ocultar la necesidad de prueba real.

Compilar ambos targets para simulador y destino iOS genérico sin firma si procede; ejecutar suite completa. Usar simulador disponible para app, extensión, App Group, persistencia, favoritos y eliminación. Revisar visualmente Light/Dark, Dynamic Type grande, iPhone compacto y iPad/orientación. Añadir tests UI cuando permitan verificar un flujo real y no solo un contenedor artificial.

`docs/VALIDATION.md` debe separar **comprobado**, **fallido** y **pendiente** con comandos y evidencia. La simulación de un controlador no equivale a teclado habilitado en Settings. La validación de permisos reales, dispositivo físico y signing puede requerir comprobación del usuario: no marcarla como superada ni ocultar la limitación.

## Entregables

Proyecto Xcode que abre y compila, fuentes Swift, entitlements/Info.plist, tests, README con setup y comandos, matriz API/versión/fallback y registro honesto de validación. Sin secretos ni datos de prueba sensibles en Git. No dar por terminada la app como producción si quedan bloqueos relevantes de ejecución.

## Plan de migración — SwiftData con App Group

**Estado:** implementado y validado en simulador. Pasan 15 tests de almacenamiento y tres flujos de interfaz, incluidos los teclados con y sin Full Access. Se conservaron los diez snippets del contenedor anterior. Los comandos y límites de validación están en `docs/VALIDATION.md`.

Actualizado el 22-09-2026 antes de implementar el cambio. SwiftData sustituirá
el JSON como fuente de verdad a partir de iOS 17. El archivo JSON existente se
conserva como entrada de migración hasta verificar la importación y después se
retira. No se actualiza ni se consulta para las operaciones normales después
de que una migración se haya completado.

### Diseño propuesto

- Añadir un `@Model` pequeño para un snippet (`UUID`, texto, fecha y favorito)
  y un segundo `@Model` de metadatos con una marca de migración. Las interfaces
  de la app y del teclado continúan intercambiando `ClipboardItem`, que es un
  valor `Sendable`; los objetos `@Model` no salen del contexto que los obtuvo.
- Crear un `ModelContainer` explícito en una URL fija dentro del App Group, con
  `ModelConfiguration(... url: ..., allowsSave: ..., cloudKitDatabase: .none)`.
  El uso de una URL explícita evita depender de la selección automática de un
  grupo y `.none` impide sincronización CloudKit.
- El teclado sin Full Access abrirá esa misma URL con `allowsSave: false`.
  No hará migraciones, no creará el archivo de bloqueo y no intentará guardar.
  Su viabilidad se debe comprobar en el teclado habilitado realmente: la firma
  de `ModelConfiguration` documenta que `allowsSave` determina si el almacén
  asociado es escribible, pero una prueba de compilación no basta para probar
  la política de una extensión.
- Cada lectura o mutación usará un contexto recién creado y se convertirá
  enseguida a DTOs. Conservar una notificación Darwin sin payload para pedir
  una recarga desde almacenamiento, en vez de mantener objetos de SwiftData
  potencialmente obsoletos entre procesos.
- Las mutaciones con Full Access conservarán un `flock` exclusivo, ahora sobre
  un archivo de coordinación independiente del almacén SQLite. Dentro del
  bloqueo se abre un contexto nuevo, se relee el estado, se modifica y se llama
  a `save()`. Eso serializa app y extensión alrededor de la comprobación de
  deduplicación y evita perder una actualización por contextos separados.
- La migración también se ejecutará bajo ese bloqueo y solo por un escritor.
  Decodificará el JSON legado, insertará todos sus UUID/fechas/favoritos y la
  marca en una única transacción, guardará, abrirá una lectura nueva para
  verificar recuento e identidad, y solo entonces completará la importación y
  eliminará el JSON legado. Si el JSON está corrupto o falla la validación, no
  se pondrá la marca y no se sobrescribirá ni borrará el legado.

### Riesgos que deben cerrarse antes de entrega

- SwiftData usa SQLite y sus archivos auxiliares. La exclusión de backup y la
  protección de archivo deben aplicarse de forma compatible a la ubicación que
  crea el contenedor y probarse en un App Group firmado; no se debe prometer
  una protección que SwiftData no permita configurar.
- `allowsSave: false` es una API pública de iOS 17, pero queda por demostrar
  que abrir una base existente de App Group desde la Keyboard Extension sin
  Full Access no intenta crear archivos auxiliares. La prueba debe medir el
  árbol de archivos antes/después, además de insertar un snippet real.
- SwiftData no sustituye por sí solo la coherencia de UI entre procesos. La
  estrategia de contexto nuevo por operación, bloqueo exclusivo de escritores
  y notificación de recarga se probará con dos instancias intercaladas y con
  app/extensión reales.
- La migración de JSON es de datos externos a SwiftData, no una
  `SchemaMigrationPlan`. Los tests deben incluir JSON válido con Unicode y
  fechas subsegundo, JSON corrupto, repetición idempotente y retirada del
  archivo legado sólo después de verificar el éxito.

### Puerta de implementación

Antes de retirar el store JSON, compilar ambos targets con SwiftData, ejecutar
las pruebas de persistencia/deduplicación/favoritos/concurrencia/migración y
repetir el flujo habilitado de teclado. La documentación de validación debe
distinguir cualquier limitación restante de solo lectura de Full Access y de
dispositivo físico.

## Documentación oficial consultada y que debe ampliar Terra

Consultada el 22-09-2026. Comprobar declaraciones del SDK y disponibilidad antes de usar cada API.

- [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)
- [UIInputViewController](https://developer.apple.com/documentation/uikit/uiinputviewcontroller)
- [UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)
- [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [UIPasteboard](https://developer.apple.com/documentation/uikit/uipasteboard)
- [UIPasteControl](https://developer.apple.com/documentation/uikit/uipastecontrol)
- [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Custom Keyboard — guía archivada, referencia histórica](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
