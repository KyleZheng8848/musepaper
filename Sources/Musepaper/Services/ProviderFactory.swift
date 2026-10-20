import Foundation

struct ProviderFactory: Sendable {
    func make(configuration: ModelConfiguration, apiKey: String?) throws -> any ImageProvider {
        switch configuration.provider {
        case .demo: return DemoImageProvider()
        case .openAI, .compatible:
            guard let apiKey, !apiKey.isEmpty else { throw MusepaperError.missingAPIKey }
            return try OpenAIImageProvider(configuration: configuration, apiKey: apiKey)
        }
    }
}
