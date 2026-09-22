import XCTest
import UIKit

final class ClipboardUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-UITestResetOnboarding"]
        app.launch()
    }

    func testOnboardingAndManualSnippetCreation() throws {
        XCTAssertTrue(app.staticTexts["onboardingPageTitle"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["onboardingPrimaryButton"].waitForExistence(timeout: 3), app.debugDescription)
        try completeOnboardingIfNeeded()
        let clipboardText = "App clipboard save \(UUID().uuidString)"
        UIPasteboard.general.string = clipboardText
        let saveFromClipboard = app.buttons["appSaveFromClipboardControl"]
        XCTAssertTrue(saveFromClipboard.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(saveFromClipboard.label, "Save from clipboard")
        tapSavingClipboard(saveFromClipboard)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", clipboardText)).firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        app.buttons["appNewSnippetControl"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("UI test snippet 👩🏽‍💻\nhttps://example.com")
        app.buttons["newSnippetSaveButton"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UI test snippet")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSpanishCoreLocalization() throws {
        app.terminate()
        app.launchArguments = ["-UITestResetOnboarding", "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()

        let pageTitle = app.staticTexts["onboardingPageTitle"]
        XCTAssertTrue(pageTitle.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(pageTitle.label, "Tus textos, listos para usar")
        let onboardingButton = app.buttons["onboardingPrimaryButton"]
        XCTAssertEqual(onboardingButton.label, "Continuar")
        onboardingButton.tap(); onboardingButton.tap(); onboardingButton.tap()

        let saveFromClipboard = app.buttons["appSaveFromClipboardControl"]
        XCTAssertTrue(saveFromClipboard.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(saveFromClipboard.label, "Guardar texto copiado")
        XCTAssertEqual(app.buttons["appNewSnippetControl"].label, "Nuevo texto")
        XCTAssertEqual(app.searchFields.firstMatch.placeholderValue, "Buscar textos")
    }

    func testKeyboardExtensionSystemFlowAttempt() throws {
        try completeOnboardingIfNeeded()
        let seedToken = UUID().uuidString
        let seedText = "Keyboard seed \(seedToken) 👩🏽‍💻"
        try createSnippet(seedText)
        let clipboardToken = UUID().uuidString
        let clipboardText = "Keyboard clipboard \(clipboardToken)"
        UIPasteboard.general.string = clipboardText
        let deleteToken = UUID().uuidString
        try createSnippet("Keyboard delete \(deleteToken)")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5), settings.debugDescription)
        // Settings can restore the Apps list from an earlier app-settings handoff. Return to root
        // using the observed public accessibility identifiers before navigating keyboard settings.
        for _ in 0..<3 {
            if settings.navigationBars["Ajustes"].waitForExistence(timeout: 3) { break }
            let appListBack = settings.navigationBars["Apps"].buttons["BackButton"]
            if appListBack.waitForExistence(timeout: 4) { appListBack.tap() }
        }
        let general = settings.buttons["com.apple.settings.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 5), settings.debugDescription)
        general.tap()
        XCTAssertTrue(settings.navigationBars["General"].waitForExistence(timeout: 4), settings.debugDescription)
        try tap(anyOf: ["Keyboard", "Teclado"], in: settings)
        // The first Keyboard page exposes the enabled-keyboards row with this stable public ID.
        let enabledKeyboards = settings.buttons["KEYBOARDS"]
        XCTAssertTrue(enabledKeyboards.waitForExistence(timeout: 4), settings.debugDescription)
        enabledKeyboards.tap()
        if settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Clipboard")).firstMatch.exists {
            try tap(anyOf: ["Clipboard"], in: settings)
        } else {
            try tapContaining(anyOf: ["Add New Keyboard", "Añadir nuevo teclado"], in: settings)
            try tap(anyOf: ["Clipboard"], in: settings)
            // Recent Settings versions show an app-selection page first. Confirm that selection
            // before opening the resulting Clipboard keyboard row for its access setting.
            let done = settings.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Hecho")).firstMatch
            if done.waitForExistence(timeout: 3) { done.tap() }
            let keyboardRow = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Clipboard")).firstMatch
            if keyboardRow.waitForExistence(timeout: 3) { keyboardRow.tap() }
        }

        // If the detail page presents the Full Access switch, enable it and accept the system confirmation.
        let fullAccess = settings.switches.matching(NSPredicate(format: "label == %@ OR label == %@", "Allow Full Access", "Permitir acceso total")).firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 3), settings.debugDescription)
        // Settings exposes a labelled accessibility wrapper and the actual narrow switch.
        // Toggle the latter, whose value reflects the user's setting.
        let fullAccessValueSwitch = settings.switches.allElementsBoundByIndex.last!
        if fullAccessValueSwitch.value as? String != "1" {
            fullAccessValueSwitch.tap()
            let confirmation = settings.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Allow", "Permitir")
            ).firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 3), settings.debugDescription)
            confirmation.tap()
            XCTAssertEqual(fullAccessValueSwitch.value as? String, "1", settings.debugDescription)
        }

        settings.terminate()
        app.launchArguments = []
        app.launch()
        app.buttons["appNewSnippetControl"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), app.debugDescription)
        editor.tap(); editor.typeText("Keyboard destination: ")

        // iOS can present its own one-time explanation for the globe key on a fresh
        // simulator. It is part of the normal system keyboard flow and must be dismissed
        // before the key can open the input-mode list.
        let keyboardTutorialContinue = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Continue", "Continuar")
        ).firstMatch
        if keyboardTutorialContinue.waitForExistence(timeout: 2) {
            keyboardTutorialContinue.tap()
        }

        // The globe is system UI. Open its input-mode list and choose the extension by
        // name, rather than relying on the order of the user's installed keyboards.
        // Detect the extension by its Recent/Favorites segment, which is available
        // regardless of Full Access.
        let globe = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Next keyboard", "Siguiente teclado")).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 3), app.debugDescription)
        globe.press(forDuration: 1.0)
        // The input-mode picker exposes keyboards as Cells (for example,
        // "Clipboard, English"), not as buttons.
        let clipboardInputMode = app.cells.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Clipboard")
        ).firstMatch
        XCTAssertTrue(clipboardInputMode.waitForExistence(timeout: 4), app.debugDescription)
        clipboardInputMode.tap()
        let keyboardSections = app.segmentedControls["clipboardKeyboardSections"]
        let clipboardKeyboardVisible = keyboardSections.buttons.element(boundBy: 0).waitForExistence(timeout: 5)
            && keyboardSections.buttons.element(boundBy: 1).exists
        guard clipboardKeyboardVisible else {
            XCTFail("Clipboard extension did not render after it was selected: \(app.debugDescription)")
            return
        }
        let snippet = app.tables["clipboardKeyboardSnippets"].cells.containing(
            NSPredicate(format: "label CONTAINS %@", seedToken)
        ).firstMatch
        guard snippet.waitForExistence(timeout: 3) else {
            XCTFail("Stored snippet was not rendered by the keyboard: \(app.debugDescription)")
            return
        }
        snippet.tap()
        XCTAssertEqual(editor.value as? String, "Keyboard destination: \(seedText)")

        let saveFromClipboard = app.buttons["clipboardSaveFromClipboardControl"]
        XCTAssertTrue(saveFromClipboard.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(saveFromClipboard.label, "Save from clipboard")
        tapSavingClipboard(saveFromClipboard)
        let clipboardSnippet = app.tables["clipboardKeyboardSnippets"].cells.containing(
            NSPredicate(format: "label CONTAINS %@", clipboardToken)
        ).firstMatch
        XCTAssertTrue(clipboardSnippet.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(editor.value as? String, "Keyboard destination: \(seedText)", "Saving must not insert into the active field.")
        clipboardSnippet.tap()
        XCTAssertEqual(editor.value as? String, "Keyboard destination: \(seedText)\(clipboardText)")

        // Full Access enables the keyboard's native favorite and delete actions.
        snippet.swipeRight()
        let favorite = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Favorite", "Favorito")).firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 3), app.debugDescription)
        favorite.tap()
        keyboardSections.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(snippet.waitForExistence(timeout: 3), app.debugDescription)
        keyboardSections.buttons.element(boundBy: 0).tap()

        let deletedSnippet = app.tables["clipboardKeyboardSnippets"].cells.containing(
            NSPredicate(format: "label CONTAINS %@", deleteToken)
        )
        XCTAssertTrue(deletedSnippet.firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        deletedSnippet.firstMatch.swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Delete", "Eliminar")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), app.debugDescription)
        delete.tap()
        XCTAssertFalse(deletedSnippet.firstMatch.waitForExistence(timeout: 3), app.debugDescription)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Clipboard keyboard Save from clipboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Relaunching the containing app verifies that the extension's favorite write
        // survives process replacement and is visible to the other target.
        app.terminate()
        app.launchArguments = []
        app.launch()
        let persistedSeedSnippet = app.cells.containing(
            NSPredicate(format: "label CONTAINS %@", seedToken)
        )
        XCTAssertTrue(persistedSeedSnippet.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(persistedSeedSnippet.count, 1)
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label CONTAINS %@", clipboardToken)).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.cells.containing(NSPredicate(format: "label CONTAINS %@", deleteToken)).firstMatch.exists)
        app.segmentedControls["clipboardKeyboardSections"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.cells.containing(
            NSPredicate(format: "label CONTAINS %@", seedToken)
        ).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testKeyboardReadsAndInsertsWithoutFullAccess() throws {
        try completeOnboardingIfNeeded()
        let token = UUID().uuidString
        let text = "Read-only keyboard \(token) 👩🏽‍💻"
        try createSnippet(text)

        let settings = try openClipboardKeyboardSettings()
        let fullAccess = settings.switches.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Allow Full Access", "Permitir acceso total")
        ).firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 3), settings.debugDescription)
        let valueSwitch = settings.switches.allElementsBoundByIndex.last!
        let wasFullAccess = valueSwitch.value as? String == "1"
        if valueSwitch.value as? String == "1" { valueSwitch.tap() }
        XCTAssertEqual(valueSwitch.value as? String, "0", settings.debugDescription)
        settings.terminate()

        app.launchArguments = []
        app.launch()
        app.buttons["appNewSnippetControl"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), app.debugDescription)
        editor.tap(); editor.typeText("Read-only destination: ")
        try selectClipboardKeyboard()

        let keyboardSections = app.segmentedControls["clipboardKeyboardSections"]
        XCTAssertTrue(keyboardSections.buttons.element(boundBy: 0).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(keyboardSections.buttons.element(boundBy: 1).exists)
        XCTAssertFalse(app.buttons["clipboardSaveFromClipboardControl"].exists, "Saving from clipboard requires Full Access.")
        let status = app.staticTexts["clipboardKeyboardStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(status.label, "Enable Full Access to save from clipboard, favorite, or delete snippets here.")
        let snippet = app.tables["clipboardKeyboardSnippets"].cells.containing(
            NSPredicate(format: "label CONTAINS %@", token)
        ).firstMatch
        XCTAssertTrue(snippet.waitForExistence(timeout: 5), app.debugDescription)
        snippet.tap()
        XCTAssertEqual(editor.value as? String, "Read-only destination: \(text)")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Clipboard keyboard without Full Access"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if wasFullAccess {
            try setClipboardKeyboardFullAccess(true)
        }
    }

    private func completeOnboardingIfNeeded() throws {
        if app.staticTexts["onboardingPageTitle"].waitForExistence(timeout: 2) {
            let onboardingButton = app.buttons["onboardingPrimaryButton"]
            onboardingButton.tap(); onboardingButton.tap(); onboardingButton.tap()
        }
    }

    private func tapSavingClipboard(_ control: XCUIElement) {
        control.tap()
        // Paste authorization is presented by the system process, so address that
        // public UI directly rather than treating it as application content.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Allow Paste", "Permitir pegar")
        ).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    private func createSnippet(_ text: String) throws {
        app.buttons["appNewSnippetControl"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), app.debugDescription)
        editor.tap(); editor.typeText(text); app.buttons["newSnippetSaveButton"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func openClipboardKeyboardSettings() throws -> XCUIApplication {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5), settings.debugDescription)
        for _ in 0..<3 {
            if settings.navigationBars["Ajustes"].waitForExistence(timeout: 3) { break }
            let appListBack = settings.navigationBars["Apps"].buttons["BackButton"]
            if appListBack.waitForExistence(timeout: 4) { appListBack.tap() }
        }
        let general = settings.buttons["com.apple.settings.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 5), settings.debugDescription)
        general.tap()
        XCTAssertTrue(settings.navigationBars["General"].waitForExistence(timeout: 4), settings.debugDescription)
        try tap(anyOf: ["Keyboard", "Teclado"], in: settings)
        let enabledKeyboards = settings.buttons["KEYBOARDS"]
        XCTAssertTrue(enabledKeyboards.waitForExistence(timeout: 4), settings.debugDescription)
        enabledKeyboards.tap()
        if settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Clipboard")).firstMatch.exists {
            try tap(anyOf: ["Clipboard"], in: settings)
        } else {
            try tapContaining(anyOf: ["Add New Keyboard", "Añadir nuevo teclado"], in: settings)
            try tap(anyOf: ["Clipboard"], in: settings)
            let done = settings.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Done", "Hecho")).firstMatch
            if done.waitForExistence(timeout: 3) { done.tap() }
            let keyboardRow = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Clipboard")).firstMatch
            if keyboardRow.waitForExistence(timeout: 3) { keyboardRow.tap() }
        }
        return settings
    }

    private func selectClipboardKeyboard() throws {
        let tutorial = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Continue", "Continuar")).firstMatch
        if tutorial.waitForExistence(timeout: 2) { tutorial.tap() }
        let globe = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@", "Next keyboard", "Siguiente teclado", "Teclado siguiente")).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 3), app.debugDescription)
        globe.press(forDuration: 1.0)
        let inputMode = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Clipboard")).firstMatch
        XCTAssertTrue(inputMode.waitForExistence(timeout: 4), app.debugDescription)
        inputMode.tap()
    }

    private func setClipboardKeyboardFullAccess(_ enabled: Bool) throws {
        let settings = try openClipboardKeyboardSettings()
        let fullAccess = settings.switches.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Allow Full Access", "Permitir acceso total")
        ).firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 3), settings.debugDescription)
        let valueSwitch = settings.switches.allElementsBoundByIndex.last!
        let isEnabled = valueSwitch.value as? String == "1"
        if isEnabled != enabled {
            valueSwitch.tap()
            if enabled {
                let confirmation = settings.buttons.matching(
                    NSPredicate(format: "label == %@ OR label == %@", "Allow", "Permitir")
                ).firstMatch
                XCTAssertTrue(confirmation.waitForExistence(timeout: 3), settings.debugDescription)
                confirmation.tap()
            }
        }
        XCTAssertEqual(valueSwitch.value as? String, enabled ? "1" : "0", settings.debugDescription)
        settings.terminate()
    }

    private func tap(anyOf labels: [String], in application: XCUIApplication) throws {
        let predicate = labels.map { "label == '\($0)'" }.joined(separator: " OR ")
        let element = application.descendants(matching: .any).matching(NSPredicate(format: predicate)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 4), "Settings items \(labels) unavailable: \(application.debugDescription)")
        element.tap()
    }

    private func tapContaining(anyOf texts: [String], in application: XCUIApplication) throws {
        let predicate = texts.map { "label CONTAINS '\($0)'" }.joined(separator: " OR ")
        let element = application.descendants(matching: .any).matching(NSPredicate(format: predicate)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 4), "Settings item containing \(texts) unavailable: \(application.debugDescription)")
        element.tap()
    }
}
