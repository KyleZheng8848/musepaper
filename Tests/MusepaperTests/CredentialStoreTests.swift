import Foundation
import XCTest
@testable import Musepaper

final class CredentialStoreTests: XCTestCase {
    func testLocalCredentialRoundTripAndPermissions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("credentials.json")
        let store = CredentialStore(fileURL: file)
        let id = UUID()

        try await store.save("local-secret", for: id)

        let exists = await store.contains(id)
        let value = try await store.read(for: id)
        XCTAssertTrue(exists)
        XCTAssertEqual(value, "local-secret")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try await store.delete(for: id)
        let existsAfterDelete = await store.contains(id)
        let valueAfterDelete = try await store.read(for: id)
        XCTAssertFalse(existsAfterDelete)
        XCTAssertNil(valueAfterDelete)
    }

    func testReclaimOrphanedSecretsOntoNewConfigurationIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("credentials.json")
        let store = CredentialStore(fileURL: file)
        let oldImage = UUID()
        let oldPrompt = UUID()
        let newImage = UUID()
        let newPrompt = UUID()

        try await store.save("shared-secret", for: oldImage)
        try await store.save("shared-secret", for: oldPrompt)

        let reclaimed = try await store.reclaimOrphanedSecrets(for: [newImage, newPrompt])
        XCTAssertEqual(reclaimed, 2)
        let imageSecret = try await store.read(for: newImage)
        let promptSecret = try await store.read(for: newPrompt)
        let containsImage = await store.contains(newImage)
        let containsPrompt = await store.contains(newPrompt)
        XCTAssertEqual(imageSecret, "shared-secret")
        XCTAssertEqual(promptSecret, "shared-secret")
        XCTAssertTrue(containsImage)
        XCTAssertTrue(containsPrompt)
    }
}
