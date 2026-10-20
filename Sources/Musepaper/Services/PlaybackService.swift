import Foundation

@MainActor
final class PlaybackService {
    private var timers: [UUID: Timer] = [:]

    func configure(playlists: [WallpaperPlaylist], action: @escaping @MainActor (UUID) -> Void) {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        for playlist in playlists where playlist.enabled {
            let interval = TimeInterval(WallpaperPlaylist.clampedIntervalSeconds(playlist.intervalSeconds))
            let id = playlist.id
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                Task { @MainActor in action(id) }
            }
            timers[id] = timer
        }
    }

    func stop() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
