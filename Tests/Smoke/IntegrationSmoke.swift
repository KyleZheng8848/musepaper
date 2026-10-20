import Foundation
import QuartzCore

@main
struct IntegrationSmoke {
    static func main() throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ reason: String) {
            precondition(value(), reason)
            checks += 1
        }
        let pool = (0..<8).map { _ in UUID() }
        var queue: [UUID] = []
        var knownPool: [UUID] = []
        var last: UUID?
        for _ in 0..<100 {
            var seen = Set<UUID>()
            for _ in pool {
                let next = PlaylistShuffle.takeNext(poolIDs: pool, queue: &queue, knownPool: &knownPool, avoiding: Set(last.map { [$0] } ?? []))!
                expect(seen.insert(next).inserted, "No repeats before the shuffle cycle ends")
                expect(next != last, "Avoid immediate repeats across cycle boundaries")
                last = next
            }
            expect(queue.isEmpty, "The bag is exhausted after a complete cycle")
        }
        let first = PlaylistShuffle.takeNext(poolIDs: pool, queue: &queue, knownPool: &knownPool)!
        let fresh = UUID()
        let grown = pool + [fresh]
        var remaining = Set<UUID>()
        for _ in 0..<pool.count {
            let next = PlaylistShuffle.takeNext(poolIDs: grown, queue: &queue, knownPool: &knownPool)!
            expect(next != first && remaining.insert(next).inserted, "Only real newcomers join an active bag")
        }
        expect(remaining.contains(fresh), "New artwork participates in the current cycle")
        queue = [pool[0], pool[1]]
        knownPool = pool
        let reduced = [pool[1], fresh]
        let selected = PlaylistShuffle.takeNext(poolIDs: reduced, queue: &queue, knownPool: &knownPool)!
        expect(Set(queue + [selected]) == Set(reduced), "Drop deleted artwork and include additions")
        expect(PlaylistShuffle.takeNext(poolIDs: [], queue: &queue, knownPool: &knownPool) == nil && queue.isEmpty && knownPool.isEmpty, "Empty pools clear stale state")
        var legacy = WallpaperPlaylist(name: "旧作品集", order: .shuffle)
        let oldData = try JSONEncoder().encode(legacy)
        let decodedLegacy = try JSONDecoder().decode(WallpaperPlaylist.self, from: oldData)
        expect(decodedLegacy.shufflePoolIDs == nil, "Legacy playlists still load")
        legacy.shuffleQueueIDs = [pool[1]]
        legacy.shufflePoolIDs = pool
        let restored = try JSONDecoder().decode(WallpaperPlaylist.self, from: JSONEncoder().encode(legacy))
        expect(restored.shuffleQueueIDs == legacy.shuffleQueueIDs && restored.shufflePoolIDs == pool, "Persist bag membership and remaining items")

        expect(ImagePromptDialect.infer(from: "LLaDA-Image") == .llada, "Recognize LLaDA")
        expect(ImagePromptDialect.infer(from: "Qwen-Image-2512-Lightning") == .qwen, "Recognize Qwen")
        expect(OpenAIImageProvider.normalizedSize(.qwenLandscapeHD, dialect: .antchat, model: "LLaDA-Image") == "1536x1024", "LLaDA uses its native landscape size")
        expect(OpenAIImageProvider.normalizedSize(.qwenLandscapeHD, dialect: .antchat, model: "Qwen-Image") == "2048x1152", "Qwen retains its high-resolution size")
        let composer = PromptComposer()
        for core in ["马尔代夫的果冻海", "一块紫水晶", "春天的悠闲午后"] {
            let prompts = (0..<4).map { composer.imageModelPrompt(core, core: core, seed: $0 + 7, model: "LLaDA-Image") }
            expect(prompts.allSatisfy { $0.contains(core) }, "Preserve Chinese subject names")
            expect(Set(prompts).count == prompts.count, "Give each candidate a distinct scene")
            expect(prompts.allSatisfy { !$0.contains("This frame differs") && !composer.containsInstructionLeak($0) }, "Image prompts contain scenes, not drafting instructions")
        }
        let ping = LivingMotion.pingPong("transform.scale", from: 1, to: 1.08, period: 16)
        let values = (ping.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        expect(values.first == values.last, "Ambient motion loops continuously")
        let walk = LivingMotion.wander("transform.scale", low: 1.05, high: 1.12, steps: 6, period: 36, seed: 7)
        let steps = (walk.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        expect(steps.count > 4 && steps.first == steps.last, "Random wander closes without a jump")
        expect(steps.allSatisfy { $0 >= 1.05 && $0 <= 1.12 }, "Random wander stays within overscan limits")
        print("INTEGRATION_SMOKE_OK checks=\(checks)")
    }
}
