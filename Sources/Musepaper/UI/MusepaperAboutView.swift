import SwiftUI

struct MusepaperAboutView: View {
    var close: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(AppIdentity.name)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("版本 \(AppVersion.display)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            Divider()
            SofunAIPublisherView()
            Link("GitHub 开源主页", destination: AppIdentity.repositoryURL)
                .accessibilityLabel("在浏览器打开 Musepaper GitHub 开源主页")
            Text(AppIdentity.copyright)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("关闭", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }
}
