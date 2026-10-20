import Foundation

/// Persists the final image Prompt beside each artwork PNG so library UI and
/// disk-recovery can still show what was actually sent to the model.
enum ArtworkPromptSidecar {
    struct Payload: Codable, Equatable, Sendable {
        var finalPrompt: String
        var rawInput: String
        var negativePrompt: String
        var coreKeywords: String
        var savedAt: Date

        init(
            finalPrompt: String,
            rawInput: String,
            negativePrompt: String,
            coreKeywords: String = "",
            savedAt: Date = Date()
        ) {
            self.finalPrompt = finalPrompt
            self.rawInput = rawInput
            self.negativePrompt = negativePrompt
            self.coreKeywords = coreKeywords
            self.savedAt = savedAt
        }

        enum CodingKeys: String, CodingKey {
            case finalPrompt, rawInput, negativePrompt, coreKeywords, savedAt
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            finalPrompt = try box.decode(String.self, forKey: .finalPrompt)
            rawInput = try box.decodeIfPresent(String.self, forKey: .rawInput) ?? ""
            negativePrompt = try box.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
            coreKeywords = try box.decodeIfPresent(String.self, forKey: .coreKeywords) ?? ""
            savedAt = try box.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        }
    }

    static func url(forImageURL imageURL: URL) -> URL {
        let name = imageURL.lastPathComponent
        let stem: String
        if let range = name.range(of: ".wallpaper-") {
            stem = String(name[..<range.lowerBound])
        } else {
            stem = imageURL.deletingPathExtension().lastPathComponent
        }
        return imageURL.deletingLastPathComponent().appendingPathComponent("\(stem).prompt.json")
    }

    @discardableResult
    static func write(
        finalPrompt: String,
        rawInput: String,
        negativePrompt: String,
        coreKeywords: String = "",
        nextTo imageURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let cleanedFinal = finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedFinal.isEmpty else { return nil }
        let payload = Payload(
            finalPrompt: cleanedFinal,
            rawInput: rawInput.trimmingCharacters(in: .whitespacesAndNewlines),
            negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            coreKeywords: coreKeywords.trimmingCharacters(in: .whitespacesAndNewlines),
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let destination = url(forImageURL: imageURL)
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    static func read(nextTo imageURL: URL) -> Payload? {
        let destination = url(forImageURL: imageURL)
        guard let data = try? Data(contentsOf: destination),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let cleaned = payload.finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return payload
    }
}

extension GenerationRecord {
    /// Prompt that was (or should have been) sent to the image model.
    var finalPromptText: String {
        let resolved = request.resolvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty { return resolved }
        return request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var ideaText: String {
        request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short theme shown in the library; full Prompt stays folded.
    var coreKeywordsText: String {
        let stored = request.coreKeywords?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }
        let idea = ideaText
        if !idea.isEmpty,
           idea != "磁盘恢复",
           idea != "磁盘找回",
           idea != finalPromptText,
           !idea.lowercased().hasSuffix(".png") {
            return idea
        }
        return ""
    }
}
