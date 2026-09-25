import SwiftData
import XCTest

final class ClipboardStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func store(_ access: ClipboardStore.Access = .readWrite) -> ClipboardStore { ClipboardStore(containerURL: directory, access: access) }

    func testPersistsUnicodeMultilineTextAndFavoriteAcrossReload() throws {
        let text = "Hello 👩🏽‍💻\nhttps://example.com/東京\nhello@example.com"
        let writer = store()
        let saved = try writer.add(text: text)
        try writer.toggleFavorite(id: saved.id)
        let reloaded = try store().load()
        XCTAssertEqual(reloaded, [ClipboardItem(id: saved.id, text: text, createdAt: saved.createdAt, isFavorite: true)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(AppGroup.swiftDataStoreFilename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(AppGroup.storeFilename).path))
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        // The simulator accepts the protection assignment but doesn't report a protection class.
        // On systems that expose it, reject a weaker unexpected value.
        if let protection = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(AppGroup.swiftDataStoreFilename).path)[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        }
    }

    func testNewestOrderingRetainsSubsecondDatesAndTieBreaksDeterministically() throws {
        let writer = store()
        let base = Date(timeIntervalSinceReferenceDate: 100)
        _ = try writer.add(text: "first", now: base)
        _ = try writer.add(text: "second", now: base.addingTimeInterval(0.0001))
        _ = try writer.add(text: "third", now: base.addingTimeInterval(0.0002))
        XCTAssertEqual(try store().load().map(\.text), ["third", "second", "first"])
        let tieA = ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, text: "tie B", createdAt: base)
        let tieB = ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "tie A", createdAt: base)
        XCTAssertEqual([tieA, tieB].newestFirst().map(\.text), ["tie A", "tie B"])
    }

    func testConsecutiveDuplicateKeepsOriginalIdentityAndFavoriteAfterReload() throws {
        let writer = store()
        let first = try writer.add(text: "repeat")
        try writer.toggleFavorite(id: first.id)
        let duplicate = try store().add(text: "repeat")
        XCTAssertEqual(duplicate.id, first.id)
        XCTAssertEqual(try store().load().filter { $0.text == "repeat" }.count, 1)
        XCTAssertTrue(try store().load().first?.isFavorite == true)
    }

    func testInterleavedStoresDoNotLoseUpdates() throws {
        let first = store(); let second = store()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { defer { group.leave() }; _ = try? first.add(text: "A") }
        group.enter(); DispatchQueue.global().async { defer { group.leave() }; _ = try? second.add(text: "B") }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(Set(try store().load().map(\.text)), Set(["A", "B"]))
    }

    func testReadOnlyDoesNotCreateFilesAndRejectsMutations() throws {
        let reader = store(.readOnly)
        let emptyDirectory = try directorySnapshot()
        XCTAssertEqual(try reader.load(), [])
        XCTAssertEqual(try directorySnapshot(), emptyDirectory)
        XCTAssertThrowsError(try reader.add(text: "nope")) { XCTAssertEqual($0 as? ClipboardStoreError, .readOnly) }
        XCTAssertThrowsError(try reader.setCloudSyncEnabled(true)) { XCTAssertEqual($0 as? ClipboardStoreError, .readOnly) }
        let writable = store(); _ = try writable.add(text: "existing")
        let afterWrite = try directorySnapshot()
        XCTAssertEqual(try reader.load().map(\.text), ["existing"])
        XCTAssertEqual(try directorySnapshot(), afterWrite, "The read-only SwiftData context must not create SQLite sidecars.")
    }

    func testModelsRemainCompatibleWithPrivateCloudKitDatabase() {
        let schema = Schema([StoredClipboardItem.self, ClipboardStoreMetadata.self])
        for entity in schema.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "CloudKit cannot mirror unique constraints on \(entity.name)")
            for attribute in entity.attributes {
                XCTAssertFalse(attribute.isUnique, "CloudKit cannot mirror \(entity.name).\(attribute.name) as unique")
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil,
                              "CloudKit needs a default for \(entity.name).\(attribute.name)")
            }
        }
    }

    func testCorruptFileIsReportedAndNeverOverwritten() throws {
        let file = directory.appendingPathComponent(AppGroup.storeFilename)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store().load()) { XCTAssertEqual($0 as? ClipboardStoreError, .corruptData) }
        XCTAssertThrowsError(try store().add(text: "must not overwrite"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testMigratesLegacyJSONOnceAndPreservesExactValues() throws {
        let base = Date(timeIntervalSinceReferenceDate: 1_234.567_89)
        let legacy = [
            ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, text: "Older 👩🏽‍💻\nhttps://example.com", createdAt: base, isFavorite: true),
            ClipboardItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "Newer 東京", createdAt: base.addingTimeInterval(0.0001), isFavorite: false)
        ]
        let legacyURL = directory.appendingPathComponent(AppGroup.storeFilename)
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        XCTAssertEqual(try store().load(), legacy.newestFirst())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(AppGroup.swiftDataStoreFilename).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "Legacy JSON is removed only after a fresh SwiftData read verifies the import.")
        XCTAssertEqual(try store().load(), legacy.newestFirst(), "The migration marker prevents a second import.")
    }

    func testReadOnlyLegacyArchiveRequiresWriterAndDoesNotCreateStore() throws {
        let legacyURL = directory.appendingPathComponent(AppGroup.storeFilename)
        try JSONEncoder().encode([ClipboardItem(text: "legacy")]).write(to: legacyURL)
        let before = try directorySnapshot()
        XCTAssertThrowsError(try store(.readOnly).load()) {
            XCTAssertEqual($0 as? ClipboardStoreError, .migrationRequiresWriteAccess)
        }
        XCTAssertEqual(try directorySnapshot(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(AppGroup.swiftDataStoreFilename).path))
    }

    func testCorruptSwiftDataFileIsPreservedAndNeverReset() throws {
        let databaseURL = directory.appendingPathComponent(AppGroup.swiftDataStoreFilename)
        let corrupt = Data("not a SQLite database".utf8)
        try corrupt.write(to: databaseURL)
        XCTAssertThrowsError(try store().load()) { XCTAssertEqual($0 as? ClipboardStoreError, .corruptData) }
        XCTAssertThrowsError(try store().add(text: "must not reset corrupt data")) { XCTAssertEqual($0 as? ClipboardStoreError, .corruptData) }
        XCTAssertEqual(try Data(contentsOf: databaseURL), corrupt)
    }

    func testDuplicateLegacyUUIDIsRejectedWithoutDeletingArchive() throws {
        let id = UUID()
        let legacyURL = directory.appendingPathComponent(AppGroup.storeFilename)
        let legacy = [
            ClipboardItem(id: id, text: "one", createdAt: .now),
            ClipboardItem(id: id, text: "two", createdAt: .now)
        ]
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: legacyURL)
        XCTAssertThrowsError(try store().load()) { XCTAssertEqual($0 as? ClipboardStoreError, .corruptData) }
        XCTAssertEqual(try Data(contentsOf: legacyURL), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(AppGroup.swiftDataStoreFilename).path))
    }

    func testInterruptedImportRecoversWithoutReparsingResidualLegacyArchive() throws {
        let item = ClipboardItem(text: "Imported before interruption", createdAt: Date(timeIntervalSinceReferenceDate: 55), isFavorite: true)
        let databaseURL = directory.appendingPathComponent(AppGroup.swiftDataStoreFilename)
        let schema = Schema([StoredClipboardItem.self, ClipboardStoreMetadata.self])
        let configuration = ModelConfiguration("Clipboard", schema: schema, url: databaseURL, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(StoredClipboardItem(item: item))
        context.insert(ClipboardStoreMetadata(key: "legacy-json-v1-imported", value: "imported"))
        try context.save()

        // This simulates a crash after the atomic item+marker save but before verification.
        // A later corrupted residual archive must not block or re-import the verified database.
        let legacyURL = directory.appendingPathComponent(AppGroup.storeFilename)
        try Data("residual legacy is corrupt".utf8).write(to: legacyURL)
        XCTAssertEqual(try store().load(), [item])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try store(.readOnly).load(), [item])
    }

    func testEmptyUnmarkedSwiftDataStoreCompletesInitialization() throws {
        let databaseURL = directory.appendingPathComponent(AppGroup.swiftDataStoreFilename)
        let schema = Schema([StoredClipboardItem.self, ClipboardStoreMetadata.self])
        let configuration = ModelConfiguration("Clipboard", schema: schema, url: databaseURL, allowsSave: true, cloudKitDatabase: .none)
        _ = try ModelContainer(for: schema, configurations: [configuration])

        XCTAssertEqual(try store().load(), [])
        XCTAssertEqual(try store(.readOnly).load(), [])
    }

    func testDeleteUpdateAndVeryLongText() throws {
        let longText = String(repeating: "長い😀", count: 20_000)
        let writer = store(); let item = try writer.add(text: longText)
        XCTAssertEqual(try store().load().first?.text, longText)
        try writer.update(id: item.id, text: "edited")
        XCTAssertEqual(try writer.load().first?.text, "edited")
        try writer.delete(id: item.id)
        XCTAssertTrue(try writer.load().isEmpty)
    }

    func testRejectsWhitespaceAndDoesNotCollapseDifferentText() throws {
        let writer = store()
        XCTAssertThrowsError(try writer.add(text: " \n\t ")) { XCTAssertEqual($0 as? ClipboardStoreError, .invalidText) }
        _ = try writer.add(text: "one")
        _ = try writer.add(text: "two")
        XCTAssertEqual(try writer.load().map(\.text), ["two", "one"])
    }

    func testUnusableContainerFailsWithoutCreatingFallbackStorage() throws {
        let fileInsteadOfDirectory = directory.appendingPathComponent("file-container")
        try Data("x".utf8).write(to: fileInsteadOfDirectory)
        let unusable = ClipboardStore(containerURL: fileInsteadOfDirectory, access: .readWrite)
        XCTAssertThrowsError(try unusable.add(text: "must not escape the group")) {
            XCTAssertEqual($0 as? ClipboardStoreError, .unableToCreateDirectory)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(AppGroup.storeFilename).path))
    }

    private func directorySnapshot() throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
    }
}
