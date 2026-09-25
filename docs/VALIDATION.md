# Validation record

The original SwiftData baseline below was validated on 22 September 2026 using Xcode 26.3, the iOS 26.2 SDK, and an iOS 26.3 simulator on an x86_64 host.

## Optional private iCloud sync — 25 September 2026

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build of app and keyboard for iOS Simulator | Passed without Swift compiler warnings | `/tmp/iosclipboard-icloud-build.log` |
| Release build for generic iOS device | Passed; compile and link only | `/tmp/iosclipboard-icloud-release.log` |
| SwiftData storage suite, including CloudKit schema and read-only extension guards | 16 passed, 0 failed | `/tmp/iosclipboard-icloud-tests-final.log` |
| Pre-CloudKit SwiftData schema opened with the new model | Passed on macOS SwiftData: UUID, Unicode text, date, favorite, and migration marker preserved | `/tmp/iosclipboard-pre-cloud-schema-migration.log` |
| App settings opt-in UI test | Passed: iCloud switch is present in app Settings, off by default; Spanish label also observed | `/tmp/iosclipboard-icloud-ui-rerun.log` |

The first opt-in UI run failed solely because the simulator displayed the correctly translated Spanish switch label and the assertion expected English. The assertion now accepts either locale, and the focused rerun passed. The keyboard has no CloudKit entitlement and opens the shared store with `.none`. The app only creates a private CloudKit container when the setting is on; the user's preference is written after container creation succeeds. Existing JSON import completes before the first enable attempt.

**Requires a signed Apple Developer setup:** register `iCloud.com.iosclipboard.app`, use matching iCloud/APNs provisioning, run the signed Debug app once with `-InitializeCloudKitSchema`, and deploy that schema to production in CloudKit Console. End-to-end export/import between two devices on the same Apple Account, behavior while offline, account changes, and stopping sync after toggling off have not been verified here. A local compile or unsigned simulator run cannot prove those CloudKit operations.

## Automated checks

### English/Spanish localization revision

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build, app and embedded keyboard extension with the shared String Catalog | Passed | `/tmp/ios-dash-localization-build.log` |
| Focused SwiftData regression tests | 15 passed, 0 failed | `/tmp/ios-dash-localization-unit.log` |
| Spanish app UI localization smoke test | Passed: onboarding, `Guardar texto copiado`, `Nuevo texto`, and `Buscar textos` | `/tmp/ios-dash-localization-es-ui.log` |
| Spanish onboarding visual capture | Captured with `Tus textos, listos para usar` and `Continuar` visible | `/tmp/ios-dash-localization-es.png` |
| Compiled Spanish resources | Present in both `Clipboard.app/es.lproj` and `ClipboardKeyboard.appex/es.lproj` | `/tmp/iOSDashClipboard-swiftdata/Build/Products/Debug-iphonesimulator/` |
| Spanish keyboard accessibility hierarchy | Observed `Recientes`, `Favoritos`, and full one-line `Guardar texto copiado` with no icon; no retained PNG because the temporary runner exited during the system keyboard handoff | `/tmp/ios-dash-localization-keyboard-ui.log` |

The localization smoke test sets `AppleLanguages=(es)` and `AppleLocale=es_ES` at launch and uses stable accessibility identifiers. The system Settings permission pages and the system keyboard/globe picker remain iOS-owned and are not asserted as app copy. The extension accessibility hierarchy was observed with Spanish `Recientes`, `Favoritos`, and the complete one-line `Guardar texto copiado` button; the temporary system keyboard handoff runner exited before a PNG could be retained, so a final keyboard screenshot still requires a clean public Settings/globe pass. The shared catalog is compiled into the extension bundle.

### Current Save from clipboard revision

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build, app and embedded extension | Succeeded; compile/link only | `/tmp/ios-dash-save-from-clipboard-final-build.log` |
| Keyboard with Full Access: explicit clipboard save, authorization, direct insertion, favorite, delete, persistence | 1 passed, 0 failed | `/tmp/ios-dash-save-from-clipboard-keyboard-ui.log` |
| Keyboard without Full Access: read-only insertion and unavailable save action | 1 passed, 0 failed | `/tmp/ios-dash-save-from-clipboard-app-readonly-ui.log` |
| Light and dark keyboard layout captures | 2 focused temporary runs passed; capture tests removed afterward | `/tmp/ios-dash-save-from-clipboard-keyboard-capture.log`, `/tmp/ios-dash-save-from-clipboard-keyboard-light-capture.log` |
| App Save from clipboard action | The focused app run reached the native authorization and saved its fresh test string; XCTest then stalled on a later, unrelated New Snippet step, so this row is visual/observed evidence rather than a passing run | `/tmp/ios-dash-save-from-clipboard-app-readonly-ui.log` |

### Earlier baselines

| Check | Result | Evidence |
| --- | --- | --- |
| Onboarding and manual snippet creation before the Save from clipboard copy revision | 1 passed, 0 failed | `/tmp/ios-dash-visual-onboarding-ui.log` |
| Keyboard system-surface Debug build and Full Access flow before this copy revision | Succeeded; 1 passed, 0 failed | `/tmp/ios-dash-keyboard-style-build.log`, `/tmp/ios-dash-keyboard-style-fullaccess.log` |
| SwiftData storage unit baseline | 15 passed, 0 failed | `/tmp/ios-dash-swiftdata-unit-final.log` |
| Earlier keyboard without Full Access baseline | 1 passed, 0 failed | `/tmp/ios-dash-swiftdata-readonly-final.log` |
| Earlier generic iOS Release compile | Succeeded; compile/link only | `/tmp/ios-dash-swiftdata-release.log` |

The current revision was validated with focused keyboard UI runs and a Debug build. The app save path was observed through its real native authorization and resulting saved row, but its focused XCTest run is recorded as incomplete because the runner waited indefinitely after that successful save. The earlier storage baseline remains relevant because this change does not alter storage. The Debug build contains the existing App Intents metadata notice and signed-binary stripping notices; it has no Swift compiler warnings.

Storage tests cover exact Unicode/emoji/multiline persistence, long text, ordering with subsecond dates and deterministic ties, favorites, edits, deletion, deduplication, concurrent writers, read-only access, backup exclusion, file-protection attributes, unavailable containers, damaged JSON and SQLite preservation, duplicate legacy identifiers, import recovery, and interrupted initialization of an empty database.

The Full Access test enables the keyboard through the public Settings UI, selects it with the system globe menu, saves a fresh clipboard value using the visible `Save from clipboard` button and accepts the native paste authorization when shown. It verifies saving does not insert into the active field, then asserts direct snippet insertion, favorite and delete swipe actions, and shared persistence after relaunch.

The test without Full Access switches that permission off in Settings, opens the same SwiftData store from the extension, verifies the read-only message and that `Save from clipboard` is unavailable, and taps a snippet once to assert exact insertion. A storage unit test also checks that read-only access leaves the shared directory contents unchanged and rejects mutation.

## Real App Group migration

The iPhone 17 simulator already contained ten synthetic snippets from the previous JSON implementation. Before upgrading, an independent snapshot recorded each UUID, creation date, favorite flag, and a SHA-256 digest of its text, without printing the snippets. After the UI test upgraded the existing installation:

- All ten records matched exactly in the SwiftData database.
- No original record was missing or changed.
- The migration marker was `verified`.
- The old `clipboard-items-v1.json` had been removed.

The audit snapshot is `/tmp/iosdash-legacy-migration-evidence.json`. The actual shared container contains `clipboard-items.store` and SQLite auxiliary files. CloudKit was explicitly disabled in this earlier migration baseline; it is now optional and off by default. Test data was synthetic; no personal clipboard content was used.

## Commands

Ad-hoc signing provides the App Group entitlement for simulator execution without a developer account. Use the simulator architecture appropriate for the host; this Mac uses x86_64.

```sh
xcodebuild -project iOSClipboard.xcodeproj -scheme Clipboard \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/iOSDashClipboard-swiftdata \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 test

xcodebuild -project iOSClipboard.xcodeproj -scheme Clipboard \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/iOSDashClipboard-swiftdata-release \
  CODE_SIGNING_ALLOWED=NO build
```

The device build verifies compilation and linking. Installing on physical hardware still requires a developer-team signature and the matching App Group capability.

## Visual checks and remaining work

- The onboarding sheet was inspected on iPhone 17 at the standard text size in [light](screenshots/onboarding-shared-surface-light.png) and [dark](screenshots/onboarding-shared-surface-dark.png). The scroll content and fixed controls share the sheet's native material; there is no opaque bar or color break above Continue.
- It was also inspected at `accessibility-extra-extra-extra-large`: [onboarding-shared-surface-accessibility-xxxl.png](screenshots/onboarding-shared-surface-accessibility-xxxl.png). The sheet selects the large detent, its title and Continue remain visible, and longer copy scrolls in the space above the fixed controls without passing beneath them.
- The current keyboard action was inspected in [light](screenshots/keyboard-save-from-clipboard-light.png) and [dark](screenshots/keyboard-save-from-clipboard-dark.png). The blue capsule keeps the complete `Save from clipboard` title on one line alongside compact rounded rows, the globe, and the microphone. [Earlier rounded-row evidence](screenshots/keyboard-rounded-snippets.png) remains useful for the row layout.
- The keyboard root is a [`UIInputView` with `.keyboard` style](https://developer.apple.com/documentation/uikit/uiinputview/style/keyboard), UIKit's public semantic style that applies the keyboard's blur and tinting. It replaces the extension's former `secondarySystemBackground` fill; no custom blur, gradient, or sampled color is drawn. The real keyboard was inspected after the change in [light](screenshots/keyboard-system-surface-light.png) and [dark](screenshots/keyboard-system-surface-dark.png): its extension surface joins the system area containing the globe and microphone while retaining compact rounded snippet rows and native contrast. The surrounding system keyboard chrome remains iOS-owned.
- The app button was inspected in [light](screenshots/save-from-clipboard-app-light.png) and [dark](screenshots/save-from-clipboard-app-dark.png). It shows the full white `Save from clipboard` label in a native blue capsule. The app and extension read `UIPasteboard` only after that tap and allow iOS to present its paste authorization; saving does not insert text into the active field. Snippets can also be created or edited with New Snippet, and selection in the real keyboard directly inserts stored text.
- The earlier keyboard without Full Access was visually inspected at `/tmp/iosdash-swiftdata-readonly-review/9CBD2131-6E6E-4184-9014-4D85A4A19F8D.png`; the list, read-only explanation, and favorite symbol layout were correct.
- Repeat the keyboard flow on physical iPhone/iPad, including landscape and larger accessibility sizes. Some simulator emoji glyphs render as missing characters even though exact Unicode assertions pass; check glyph presentation on hardware.
- Exercise secure fields and phone-pad contexts on hardware. iOS controls custom keyboard availability for these fields.
- Confirm physical-device data protection and repeat the signed App Group smoke test.
