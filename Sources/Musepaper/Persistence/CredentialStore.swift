import Foundation

/// CPET-style plain local configuration. It deliberately has no Security
/// framework or Keychain dependency, so ad-hoc builds can never trigger a
/// system password dialog. The file remains owner-readable/writable only.
actor CredentialStore {
    private struct Payload: Codable {
        var secrets: [String: String] = [:]
    }

    private let fileURL: URL
    private var cached: Payload?

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Musepaper", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("credentials.json")
    }

    func save(_ secret: String, for configurationID: UUID) throws {
        let value = OpenAIImageProvider.sanitizeAPIKey(secret)
        guard !value.isEmpty else { throw MusepaperError.missingAPIKey }
        var payload = try load()
        let account = configurationID.uuidString
        payload.secrets[account] = value
        try persist(payload)
    }

    func read(for configurationID: UUID) throws -> String? {
        let payload = try load()
        let account = configurationID.uuidString
        return payload.secrets[account].flatMap { $0.isEmpty ? nil : $0 }
    }

    func contains(_ configurationID: UUID) async -> Bool {
        (try? read(for: configurationID))?.isEmpty == false
    }

    func delete(for configurationID: UUID) throws {
        var payload = try load()
        let account = configurationID.uuidString
        payload.secrets.removeValue(forKey: account)
        try persist(payload)
    }

    /// When model config IDs are regenerated, secrets can become orphaned.
    /// Rebind leftover values onto any requested IDs that are still empty.
    /// Returns how many target IDs received a recovered secret.
    @discardableResult
    func reclaimOrphanedSecrets(for configurationIDs: [UUID]) throws -> Int {
        let targets = configurationIDs.map(\.uuidString)
        guard !targets.isEmpty else { return 0 }
        var payload = try load()
        let targetSet = Set(targets)
        let missing = targets.filter { key in
            guard let value = payload.secrets[key] else { return true }
            return value.isEmpty
        }
        guard !missing.isEmpty else { return 0 }

        let orphans = payload.secrets.filter { !targetSet.contains($0.key) && !$0.value.isEmpty }
        guard !orphans.isEmpty else { return 0 }

        var frequency: [String: Int] = [:]
        for value in orphans.values {
            frequency[value, default: 0] += 1
        }
        var rankedValues = frequency.keys.sorted {
            let left = frequency[$0] ?? 0
            let right = frequency[$1] ?? 0
            if left != right { return left > right }
            return $0 < $1
        }

        var reclaimed = 0
        for key in missing {
            let alreadyBound = targets.compactMap { payload.secrets[$0] }.first { !$0.isEmpty }
            if let alreadyBound {
                payload.secrets[key] = alreadyBound
                reclaimed += 1
                continue
            }
            guard let next = rankedValues.first else { break }
            payload.secrets[key] = next
            rankedValues.removeFirst()
            reclaimed += 1
        }

        if reclaimed > 0 {
            try persist(payload)
        }
        return reclaimed
    }

    private func load() throws -> Payload {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = Payload()
            cached = empty
            return empty
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: fileURL))
            cached = payload
            return payload
        } catch {
            throw MusepaperError.persistenceFailed("本机 AK 凭据读取失败：\(error.localizedDescription)")
        }
    }

    private func persist(_ payload: Payload) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            cached = payload
        } catch {
            throw MusepaperError.persistenceFailed("本机 AK 凭据保存失败：\(error.localizedDescription)")
        }
    }
}
