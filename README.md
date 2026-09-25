# iOS Clipboard

Native iOS clipboard manager whose main product is a Custom Keyboard Extension. Snippets stay on the device by default in an App Group shared by the app and keyboard. An optional switch in the app synchronizes saved snippets through the user's private iCloud database. There is no app account, analytics, advertising, or third-party runtime dependency.

## Requirements and setup

- Xcode 26.3; iOS deployment target 17.0. The project was built against the installed iOS 26.2 SDK and simulator runtime 26.3.
- In **Signing & Capabilities**, select your development team for both targets and create/enable the App Group `group.com.iosclipboard.shared` for both bundle IDs. The placeholder IDs are `com.iosclipboard.app` and `com.iosclipboard.app.keyboard`.
- For iCloud sync, create the CloudKit container `iCloud.com.iosclipboard.app` in your Apple Developer team and associate it with the app target. The app target declares iCloud/CloudKit, Push Notifications, and Background Modes > Remote notifications; the keyboard target only needs the App Group. If you change the app bundle ID, update the CloudKit identifier in the app entitlements and `AppGroup.swift` together. Use automatic signing so the provisioning profile supplies the matching iCloud and APNs entitlements. Before distributing, initialize the CloudKit development schema and deploy it to production in CloudKit Console.
- To initialize the development schema once, run a signed Debug build of the app with launch argument `-InitializeCloudKitSchema` while signed in to an iCloud account. The debug initializer uses a disposable local store and reports failures in Xcode. Verify the new record types in CloudKit Console, then deploy the schema to production before a release build is distributed.
- Install the app, then enable **Clipboard** under Settings > General > Keyboard > Keyboards > Add New Keyboard. Use the globe key to switch.

The keyboard reads and inserts existing snippets without Full Access. Enable **Allow Full Access** to save from clipboard, favorite, or delete snippets from the keyboard. The keyboard does not connect to CloudKit; only the containing app uses iCloud after the user enables sync.

Open **Settings** inside Clipboard to turn **Sync with iCloud** on or off. It starts off and remains off unless the user enables it. CloudKit uses each Apple Account's private database, so snippets sync only to that person's devices signed in to the same account. Turning sync off leaves the local snippets available and stops new CloudKit mirroring from this app; it does not delete copies already stored in iCloud. Sync needs a signed app, an iCloud account, and network access. Keyboard changes can reach other devices when the containing app next processes the shared store.

Use the blue **Save from clipboard** button in the app or keyboard to explicitly save clipboard text or a URL. It reads `UIPasteboard` only after that tap, so iOS can present its native paste authorization when needed. Create or edit snippets with **New Snippet** and the system text editor. Tapping a stored snippet inserts it directly into the active field.

## Build and test

```sh
xcodebuild -project iOSClipboard.xcodeproj -scheme Clipboard \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build

# Ad-hoc signing gives the simulator the App Group entitlement. It needs no
# developer account, but uses the host simulator architecture.
xcodebuild -project iOSClipboard.xcodeproj -scheme Clipboard \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/iOSClipboard-test \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 test
```

## Storage behavior

`ClipboardStore` uses **SwiftData** with `@Model` records in `clipboard-items.store` inside the App Group. Both targets open the same store URL. The keyboard always uses `cloudKitDatabase: .none`. The app uses `.none` by default and retains a CloudKit-backed `ModelContainer` only while sync is enabled. Contexts stay within each storage operation; the UI receives value-type snapshots. Writers serialize fetch/change/save operations with an advisory process lock, and Darwin notifications trigger fresh reads between the app and keyboard. The schema uses defaults instead of SwiftData unique constraints to support CloudKit.

Without Full Access, the keyboard opens an existing store using `allowsSave: false`; it does not initialize or migrate storage. Reading and inserting from that configuration were verified in the enabled simulator keyboard. Backup exclusion is applied before creating the database, and the directory and database use `completeUntilFirstUserAuthentication` file protection. Physical-device protection behavior still requires a device smoke test. When sync is off, locally stored snippets are lost if the app is deleted or the device is replaced.

The previous `clipboard-items-v1.json` is only a migration input. Import preserves UUIDs, exact text, dates, and favorites, with durable `imported` and `verified` states to recover after interruption. The archive is removed only after verification. Invalid archives and damaged databases are reported without resetting them or falling back to JSON. The migration preserved all ten existing test snippets in the simulator's real shared container.

Only immediately consecutive identical saves are deduplicated. The original item ID and favorite state remain unchanged. Text is preserved exactly, including Unicode, emoji, URLs, whitespace inside content, and newlines; all-whitespace input is rejected.

## iOS limits

Apple replaces third-party keyboards for secure text fields and some phone-pad contexts, and host apps can disallow custom keyboards. Clipboard does not monitor the clipboard or read it in the background. It reads it only after the user taps **Save from clipboard**; users can also create snippets in the app and select them in the keyboard.
