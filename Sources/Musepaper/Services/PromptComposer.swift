import Foundation

enum ImagePromptDialect: Equatable, Sendable {
    case qwen
    case llada
    case generic

    static func infer(from model: String) -> ImagePromptDialect {
        let name = model.lowercased()
        if name.contains("llada") { return .llada }
        if name.contains("qwen") { return .qwen }
        return .generic
    }
}

struct PromptFramePlan: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case figure
        case named
        case mood
    }

    var core: String
    var kind: Kind
    var light: String
    var textRisk: Bool
    var wantsNight: Bool
    var wantsFog: Bool
    var wantsRain: Bool
    var dialect: ImagePromptDialect
}

struct PromptComposer: Sendable {
    private let variationPlanner = VariationPlanner()

    func resolve(draft: PromptDraft, channel: InspirationChannel?, display _: DisplayProfile, seed: Int? = nil) throws -> String {
        let idea = sanitizeVisualPrompt(draft.input)
        if draft.mode == .inspiration, let channel, !channel.isSchemaTemplate {
            let source = usableVisual(idea) ?? usableVisual(channel.essence) ?? "开阔的风景"
            let combo = variationPlanner.plan(
                idea: source, count: 1, seed: seed ?? 0, customAxes: channel.resolvedVariationAxes
            )[0]
            return weave(idea: source, combo: combo, draft: draft, channel: channel)
        }
        guard !idea.isEmpty else { throw MusepaperError.emptyPrompt }
        if let seed {
            let combo = variationPlanner.plan(idea: idea, count: 1, seed: seed)[0]
            return weave(idea: idea, combo: combo, draft: draft, channel: channel)
        }
        guard draft.treatment == .enhanced else { return idea }
        return idea
    }

    func weave(idea: String, combo: VariationCombo, draft: PromptDraft = PromptDraft(), channel: InspirationChannel? = nil) -> String {
        let cleanedIdea = sanitizeVisualPrompt(idea)
        var parts: [String] = []
        if let subject = usableVisual(cleanedIdea) {
            parts.append(subject)
        } else if let locked = usableVisual(channel?.lockedCore ?? "") {
            parts.append(locked)
        }
        parts.append(combo.visualPhrase)
        if let channel, !channel.isSchemaTemplate {
            appendVisual(&parts, channel.mustInclude)
        }
        if draft.treatment == .enhanced, let channel, !channel.isSchemaTemplate {
            parts.append(variationHint(channel.variation))
        }
        let joined = uniqued(parts.map(sanitizeVisualPrompt).filter { !$0.isEmpty }).joined(separator: "，")
        return groundIfNeeded(joined, core: cleanedIdea, seed: joined.hashValue)
    }

    /// Final text sent to the image model. Only describe what should be visible.
    /// Listing “no text / 没有文字 / 避免：文字” in the positive prompt makes
    /// many models paint those words onto the wallpaper.
    func enforcePureArtwork(_ prompt: String) -> String {
        sanitizeVisualPrompt(prompt)
    }

    /// Last mile before the image API.
    /// Named subjects keep the user's words (including CJK). Mood-only cores
    /// go to English so adjective piles are less likely to be painted as captions.
    /// The visible thing rotates: person / empty place / still life / interior.
    /// Instruction Chinese (没有文字 / 招牌) is stripped.
    func imageModelPrompt(_ scene: String, core: String = "", seed: Int = 0, model: String = "") -> String {
        let dialect = ImagePromptDialect.infer(from: model)
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        let incoming = sanitizeVisibleArtwork(scene.trimmingCharacters(in: .whitespacesAndNewlines), core: locked, dialect: dialect)
        var body = groundIfNeeded(incoming.isEmpty ? locked : incoming, core: locked, seed: seed)
        if dialect == .llada {
            return lladaImageScene(core: locked, seed: seed, scene: incoming)
        }
        body = stripInstructionEcho(sanitizeVisibleArtwork(body, core: locked, dialect: dialect))
        if needsGroundedScene(locked) {
            var english = containsCJK(body) ? translateToImageEnglish(body) : collapseEnglish(body)
            let englishCore = containsCJK(locked) ? translateToImageEnglish(locked) : collapseEnglish(locked)
            english = collapseEnglish(stripCJK(english))
            english = stripInstructionEcho(english)
            if english.split(whereSeparator: { $0.isWhitespace || $0 == "," }).count < 4 {
                english = fallbackEnglishScene(core: locked, seed: seed)
            }
            if !hasConcreteSubject(english) {
                english = collapseEnglish([english, needsGroundedScene(locked) ? moodSightingEnglish(seed: seed) : englishCore].filter { !$0.isEmpty }.joined(separator: ", "))
            }
            if !englishCore.isEmpty, !english.localizedCaseInsensitiveContains(englishCore) {
                english = collapseEnglish("\(englishCore), \(english)")
            }
            return wrapImagePrompt(collapseEnglish(stripCJK(english)), core: locked, dialect: dialect)
        }
        body = pinCore(locked, onto: body)
        body = stripInstructionEcho(body)
        guard !body.isEmpty else { return wrapImagePrompt(locked, core: locked, dialect: dialect) }
        return wrapImagePrompt(body, core: locked, dialect: dialect)
    }

    func finishAgentPrompt(_ scene: String, core: String, seed: Int = 0, model: String = "") -> String {
        let dialect = ImagePromptDialect.infer(from: model)
        if dialect == .llada {
            return lladaImageScene(core: core, seed: seed, scene: scene)
        }
        var body = sanitizeVisibleArtwork(scene, core: core, dialect: dialect)
        body = groundIfNeeded(body, core: core, seed: seed)
        body = pinCore(core, onto: body)
        body = stripInstructionEcho(body)
        return wrapImagePrompt(body, core: core, dialect: dialect)
    }

    /// LLaDA is bilingual. Keep the user's Chinese subject. Only strip instruction echo
    /// (Those characters / 写着 / This frame differs) — never translate 晶石 away.
    func promptFrame(core: String, seed: Int = 0) -> (light: String, view: String) {
        lladaFramePair(core: core, seed: seed)
    }

    func lladaImageScene(core: String, seed: Int = 0, scene: String = "") -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        let incoming = sanitizeVisibleArtwork(scene, core: locked, dialect: .llada)
        if usableLladaAgentBody(incoming, core: locked) {
            var body = incoming
            if !locked.isEmpty, !body.contains(locked) {
                body = pinCore(locked, onto: body)
            }
            body = stripUnrequestedGloom(body, core: locked)
            body = collapseStripDebris(stripInstructionEcho(body))
            let (light, view) = lladaFramePair(core: locked, seed: seed)
            if !body.contains(light) {
                body = containsCJK(body) ? "\(body)，\(light)" : "\(body), \(light)"
            }
            if !body.contains(view) {
                body = containsCJK(body) ? "\(body)，\(view)" : "\(body), \(view)"
            }
            if containsCJK(body), !body.contains("电影感照片") {
                body = "一张电影感照片，\(body)"
            } else if !containsCJK(body), !body.lowercased().contains("cinematic photograph") {
                body = "A cinematic photograph of \(body)"
            }
            return containsCJK(body) ? collapseSeparators(body) : collapseEnglish(body)
        }
        var subject = neutralizeSignLettering(locked, core: locked)
        subject = stripUnrequestedGlyphCarriers(subject, core: locked)
        subject = stripInstructionEcho(subject)
        subject = collapseStripDebris(subject)
        if subject.isEmpty { subject = locked }
        if subject.lowercased().hasPrefix("a cinematic photograph of") {
            subject = String(subject.dropFirst("a cinematic photograph of".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if subject.hasPrefix("一张电影感照片") {
            subject = subject.replacingOccurrences(of: "一张电影感照片，", with: "")
            subject = subject.replacingOccurrences(of: "一张电影感照片:", with: "")
            subject = subject.replacingOccurrences(of: "一张电影感照片：", with: "")
        }
        let (light, view) = lladaFramePair(core: locked, seed: seed)
        if containsCJK(subject) {
            return collapseSeparators("一张电影感照片，\(subject)，\(light)，\(view)")
        }
        return collapseEnglish("A cinematic photograph of \(subject), \(light), \(view)")
    }

    func usableLladaAgentBody(_ scene: String, core: String) -> Bool {
        let text = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 6, text.count <= 220 else { return false }
        guard !containsInstructionLeak(text) else { return false }
        guard !text.contains("写着") else { return false }
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        if !locked.isEmpty {
            return text.contains(locked) || hasConcreteSubject(text)
        }
        return hasConcreteSubject(text)
    }

    private func lladaFramePair(core: String, seed: Int) -> (String, String) {
        let zh = containsCJK(core)
        let lights: [String]
        if wantsNightWeather(core) {
            lights = wantsRainWeather(core)
                ? (zh ? ["雨夜的光", "湿雨夜里的街", "雨和霓虹"] : ["wet night light", "rain-soaked night streets", "dark rain and neon"])
                : (zh ? ["夜光", "月光", "城市夜灯"] : ["night light", "moonlit night", "city lights at night"])
        } else if wantsFogWeather(core) {
            lights = zh ? ["薄雾柔光", "晨雾", "雾里的光"] : ["soft misty light", "pale morning mist", "diffused fog light"]
        } else if wantsRainWeather(core) {
            lights = zh ? ["雨天日光", "白日里的雨", "阴雨天光"] : ["wet daylight", "rain on a bright day", "overcast rain light"]
        } else {
            lights = zh
                ? ["晴朗日光", "柔和晨光", "午后暖光", "正午强光"]
                : ["bright natural daylight", "soft morning light", "warm late-afternoon light", "clear high-sun light"]
        }
        let views: [String]
        if isFigureSubject(core) {
            views = zh
                ? ["浅景深", "四分之三人像", "更近的人像", "环境人像"]
                : ["shallow depth of field", "three-quarter portrait view", "closer portrait framing", "wide environmental portrait"]
        } else if isStillLifeObject(core) {
            views = zh
                ? ["静物特写", "切面占满画面", "物件四分之三视角", "物件贴近镜头"]
                : ["close-up still life", "macro facets filling the frame", "three-quarter object view", "the object close to the lens"]
        } else if isAerialSubject(core) {
            views = zh
                ? ["广角", "更近的航拍", "斜侧航拍", "高空晴空"]
                : ["wide-angle photograph", "closer aerial framing", "oblique aerial view", "high clear-air vantage"]
        } else {
            views = zh
                ? ["广角", "更近", "稍低机位", "稍高机位"]
                : ["wide-angle photograph", "closer framing", "slightly lower vantage", "slightly higher vantage"]
        }
        let pack = abs(seed)
        return (lights[pack % lights.count], views[(pack / lights.count) % views.count])
    }

    func framePlan(core: String, seed: Int, model: String = "") -> PromptFramePlan {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        let kind: PromptFramePlan.Kind
        if isFigureSubject(locked) {
            kind = .figure
        } else if needsGroundedScene(locked) {
            kind = .mood
        } else {
            kind = .named
        }
        let night = wantsNightWeather(locked)
        let fog = wantsFogWeather(locked)
        let rain = wantsRainWeather(locked)
        let light: String
        if night {
            light = rain ? "rainy night light matching the subject" : "night light matching the subject"
        } else if fog {
            light = "soft natural light in the mist the subject already names"
        } else if rain {
            light = "wet daylight, rain as the subject asked"
        } else {
            light = Self.daylightClimates[abs(seed) % Self.daylightClimates.count]
        }
        return PromptFramePlan(
            core: locked,
            kind: kind,
            light: light,
            textRisk: hasTextRisk(locked),
            wantsNight: night,
            wantsFog: fog,
            wantsRain: rain,
            dialect: ImagePromptDialect.infer(from: model)
        )
    }

    func hasTextRisk(_ text: String) -> Bool {
        Self.textRiskKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func wantsNightWeather(_ text: String) -> Bool {
        Self.nightWeatherKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func wantsFogWeather(_ text: String) -> Bool {
        Self.fogWeatherKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func wantsRainWeather(_ text: String) -> Bool {
        Self.rainWeatherKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func isAerialSubject(_ text: String) -> Bool {
        Self.aerialSubjectKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    /// Variation climate must not override the frame plan's light.
    func alignVariationHint(_ raw: String, to plan: PromptFramePlan) -> String {
        var text = usableVisual(raw) ?? sanitizeVisualPrompt(raw)
        guard !text.isEmpty else { return "" }
        if !plan.wantsFog {
            text = stripListedPhrases(text, Self.fogTropes + Self.unrequestedFogHints)
        }
        if !plan.wantsNight {
            text = stripListedPhrases(text, Self.nightTropes + Self.unrequestedNightHints)
        }
        return collapseStripDebris(text)
    }

    /// LLaDA only gets one short visible clause — long essays get painted as captions.
    func shortVisualClause(_ raw: String) -> String {
        let text = usableVisual(raw) ?? sanitizeVisualPrompt(raw)
        guard !text.isEmpty else { return "" }
        let clause = text.split(whereSeparator: { "，,。；;、".contains($0) }).first.map(String.init) ?? text
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 16 { return trimmed }
        return String(trimmed.prefix(16))
    }

    private func stripListedPhrases(_ scene: String, _ phrases: [String]) -> String {
        var result = scene
        for phrase in phrases.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        return result
    }

    func collapseStripDebris(_ text: String) -> String {
        var result = containsCJK(text) ? collapseSeparators(text) : collapseEnglish(text)
        result = result.replacingOccurrences(
            of: #"[,，]\s*[里着上下的了在]\s*(?=[,，]|$)"#,
            with: "，",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?:^|[,，]\s*)[里着上下的了在](?=[,，]|$)"#,
            with: "，",
            options: .regularExpression
        )
        return containsCJK(result) ? collapseSeparators(result) : collapseEnglish(result)
    }

    private func wrapImagePrompt(_ body: String, core: String, dialect: ImagePromptDialect) -> String {
        var text = containsCJK(body) ? collapseSeparators(body) : collapseEnglish(body)
        if dialect == .llada {
            text = stripUnrequestedGloom(text, core: core)
        }
        guard !text.isEmpty else {
            return emptyWrap(core: core, dialect: dialect)
        }
        let head = wallpaperWrapHead(core: core, dialect: dialect)
        if dialect != .llada,
           text.localizedCaseInsensitiveContains("photorealistic photograph"),
           text.localizedCaseInsensitiveContains("fills the frame") {
            return text
        }
        if containsCJK(text) {
            return "\(head), \(collapseSeparators(text))"
        }
        return collapseEnglish("\(head), \(text)")
    }

    private func emptyWrap(core: String, dialect: ImagePromptDialect) -> String {
        wallpaperWrapHead(core: core, dialect: dialect)
    }

    /// Visual wallpaper grammar only. Never say wallpaper / desktop / 壁纸 —
    /// those words get painted or turned into a mockup.
    private func wallpaperWrapHead(core: String, dialect: ImagePromptDialect) -> String {
        let frame = "fills the frame"
        if dialect == .llada {
            // Short lighting words only. Full sentences get painted as captions.
            if isFigureSubject(core) {
                return wantsNightWeather(core) || wantsFogWeather(core)
                    ? "natural-color portrait photograph, clear air"
                    : "natural-color portrait photograph, even daylight, clear air"
            }
            if wantsNightWeather(core) || wantsFogWeather(core) {
                return "natural-color photograph, clear air"
            }
            if hasTextRisk(core) || needsGroundedScene(core) {
                return "natural-color photograph, even daylight, clear air"
            }
            return "natural-color photograph, clear air"
        }
        if isFigureSubject(core) {
            return "photorealistic portrait photograph, \(frame)"
        }
        return "photorealistic photograph, \(frame)"
    }

    func stripInstructionEcho(_ scene: String) -> String {
        var result = scene
        for phrase in Self.instructionEchoPhrases.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        result = result.replacingOccurrences(
            of: #"those\s+characters[\w\s,.'’]*subject\s+name"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\bare the\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return collapseStripDebris(result)
    }

    private func sanitizeVisibleArtwork(_ scene: String, core: String, dialect: ImagePromptDialect) -> String {
        // Keep the cues (e.g. “写着” and “Those characters”) until their whole
        // clauses are removed; generic sanitization otherwise leaves orphaned words.
        let described = neutralizeSignLettering(stripInstructionEcho(scene), core: core)
        var text = enforcePureArtwork(stripUnrequestedGlyphCarriers(described, core: core))
        if dialect == .llada {
            text = stripUnrequestedGloom(text, core: core)
        }
        return text
    }

    func stripUnrequestedGloom(_ scene: String, core: String) -> String {
        var result = scene
        if !wantsNightWeather(core) {
            for phrase in Self.nightTropes.sorted(by: { $0.count > $1.count }) {
                result = result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
            }
        }
        if !wantsFogWeather(core) {
            for phrase in Self.fogTropes.sorted(by: { $0.count > $1.count }) {
                result = result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
            }
        }
        if !core.localizedCaseInsensitiveContains("电影") && !core.localizedCaseInsensitiveContains("cinematic") {
            result = result.replacingOccurrences(of: "cinematic", with: " ", options: .caseInsensitive)
        }
        if !core.contains("剪影") && !core.localizedCaseInsensitiveContains("silhouette") {
            result = result.replacingOccurrences(of: "剪影", with: " ")
            result = result.replacingOccurrences(of: "silhouette", with: " ", options: .caseInsensitive)
        }
        return collapseStripDebris(result)
    }

    func neutralizeSignLettering(_ scene: String, core: String) -> String {
        var result = scene
        result = result.replacingOccurrences(
            of: #"写着[^，,。.\s]{1,24}"#,
            with: "空白表面",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?:says|reads)\s+["']?[\w\-]{1,24}"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        if hasTextRisk(core) {
            for phrase in ["欢迎光临", "欢迎"] {
                if core.contains(phrase) { continue }
                result = result.replacingOccurrences(of: phrase, with: " ")
            }
        }
        if hasTextRisk(core), containsCJK(core) {
            result = stripInventedLatinMarks(result, core: core)
        }
        if hasTextRisk(core), core.contains("黑板") || core.localizedCaseInsensitiveContains("chalkboard") {
            result = result.replacingOccurrences(of: "黑板上，", with: "")
            result = result.replacingOccurrences(of: "黑板上", with: "黑板")
            let alreadyBlank = result.contains("空白")
                || result.contains("空着")
                || result.contains("深色空板")
                || result.localizedCaseInsensitiveContains("blank")
                || result.localizedCaseInsensitiveContains("unused")
            if !alreadyBlank {
                result = containsCJK(result) ? result + "，深色空板" : collapseEnglish(result + ", unused blank chalkboard")
            }
        }
        return collapseStripDebris(result)
    }

    private func stripInventedLatinMarks(_ scene: String, core: String) -> String {
        let pattern = try! NSRegularExpression(pattern: #"\b[A-Za-z][A-Za-z0-9\-.]{2,}\b"#)
        let range = NSRange(scene.startIndex..<scene.endIndex, in: scene)
        var result = scene
        for match in pattern.matches(in: scene, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: scene) else { continue }
            let token = String(scene[swiftRange])
            if core.localizedCaseInsensitiveContains(token) { continue }
            if token.localizedCaseInsensitiveContains("mm") { continue }
            result.replaceSubrange(swiftRange, with: " ")
        }
        return result
    }

    /// Library / Agent rewrite. Named subjects keep the user's name.
    /// Mood-only cores become a spoken English sighting, not a fixed empty yard.
    func spokenRewrite(_ scene: String, core: String, seed: Int = 0) -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        var body = neutralizeSignLettering(stripUnrequestedGlyphCarriers(enforcePureArtwork(scene), core: locked), core: locked)
        if needsGroundedScene(locked) {
            if containsCJK(body) { body = translateToImageEnglish(body) }
            body = collapseEnglish(stripCJK(body))
            if body.split(whereSeparator: { $0.isWhitespace || $0 == "," }).count < 4 {
                body = fallbackEnglishScene(core: locked, seed: seed)
            } else if !hasConcreteSubject(body) {
                body = collapseEnglish("\(body), \(moodSightingEnglish(seed: seed))")
            }
            return collapseEnglish(stripCJK(body))
        }
        return pinCore(locked, onto: body)
    }

    func spokenHint(_ raw: String) -> String {
        let cleaned = usableVisual(raw) ?? sanitizeVisualPrompt(raw)
        guard !cleaned.isEmpty else { return "" }
        if !containsCJK(cleaned) { return collapseEnglish(cleaned) }
        let translated = translateToImageEnglish(cleaned)
        return translated.isEmpty ? cleaned : translated
    }

    func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }

    func containsInstructionLeak(_ prompt: String) -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if Self.leakMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) { return true }
        if isSchemaPlaceholder(text) { return true }
        if text.range(of: Self.resolutionPattern, options: .regularExpression) != nil { return true }
        return false
    }

    func isSchemaPlaceholder(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return false }
        return Self.schemaPlaceholders.contains { compact.localizedCaseInsensitiveContains($0) }
    }

    func uniqueScenePrompt(
        idea: String,
        channel: InspirationChannel?,
        emptySpace: EmptySpace,
        baseline: String = "",
        index: Int,
        seed: Int
    ) -> String {
        let sharedSeed = seed &- index
        let prompts = uniqueScenePrompts(
            idea: idea, channel: channel, emptySpace: emptySpace,
            baseline: baseline, seedBase: sharedSeed, count: 4
        )
        return prompts[abs(index) % prompts.count]
    }

    func uniqueScenePrompts(
        idea: String,
        channel: InspirationChannel?,
        emptySpace: EmptySpace,
        baseline: String = "",
        seedBase: Int,
        count: Int
    ) -> [String] {
        let subject = visualSubject(idea: idea, channel: channel, baseline: baseline)
        let combos = variationPlanner.plan(
            idea: subject,
            count: InspirationChannel.clampedCount(count),
            seed: seedBase,
            customAxes: channel?.resolvedVariationAxes ?? ""
        )
        var draft = PromptDraft()
        draft.input = subject
        draft.emptySpace = emptySpace
        draft.treatment = .enhanced
        draft.mode = channel == nil ? .direct : .inspiration
        var used = Set<String>()
        return combos.enumerated().map { index, combo in
            var scene = weave(idea: subject, combo: combo, draft: draft, channel: channel)
            if !subject.isEmpty, !scene.contains(subject) {
                scene = subject + "，" + scene
            }
            return distinguish(scene, used: &used, index: index, seed: seedBase, core: subject)
        }
    }

    func distinguish(_ prompt: String, used: inout Set<String>, index: Int, seed: Int, core: String = "") -> String {
        var scene = pinCore(core, onto: enforcePureArtwork(prompt))
        if !containsCJK(scene) {
            scene = collapseEnglish(scene)
            if scene.isEmpty || containsInstructionLeak(scene) {
                scene = spokenRewrite(core, core: core, seed: seed &+ index)
            }
            var bump = 0
            let extras = Self.englishDistinguishExtras
            while used.contains(scene) && bump < extras.count {
                scene = collapseEnglish(scene + ", " + extras[(index + bump) % extras.count])
                bump += 1
            }
            used.insert(scene)
            return scene
        }
        if scene.isEmpty || containsInstructionLeak(scene) {
            let combo = variationPlanner.plan(idea: core.isEmpty ? "开阔的风景" : core, count: 4, seed: seed)[abs(index) % 4]
            scene = pinCore(core, onto: enforcePureArtwork((core.isEmpty ? "开阔的风景" : core) + "，" + combo.visualPhrase))
        }
        var bump = 0
        while used.contains(scene) && bump < 8 {
            bump += 1
            let planIdea = core.isEmpty ? scene : core
            let extra = variationPlanner.plan(idea: planIdea, count: 4, seed: seed &+ bump &* 31)[abs(index + bump) % 4]
            scene = pinCore(core, onto: withVisualVariation(scene, cue: extra.visualPhrase))
        }
        used.insert(scene)
        return scene
    }

    func userCore(idea: String, channel: InspirationChannel?) -> String {
        if let typed = usableVisual(idea) { return typed }
        return usableVisual(channel?.lockedCore ?? "") ?? "开阔的风景"
    }

    /// Immutable core must lead the final prompt. Synonym rewrites are never accepted as a substitute.
    func pinCore(_ core: String, onto scene: String) -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        var body = enforcePureArtwork(scene)
        if locked.isEmpty { return body }
        if body == locked { return locked }

        // Already correctly led by the exact core — keep as-is (avoid duplicating).
        if body.hasPrefix(locked + "，")
            || body.hasPrefix(locked + ",")
            || body.hasPrefix(locked + "、") {
            return ensureCoreTokens(locked, in: body)
        }

        // Pull exact core out of the middle/end so we can re-anchor it at the front.
        if let range = body.range(of: locked) {
            body.removeSubrange(range)
            body = collapseSeparators(body)
        }

        let anchored = body.isEmpty ? locked : "\(locked)，\(body)"
        return ensureCoreTokens(locked, in: anchored)
    }

    /// Every significant core token (split on Chinese/English separators) must still appear.
    func ensureCoreTokens(_ core: String, in scene: String) -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        guard !locked.isEmpty else { return enforcePureArtwork(scene) }
        var result = enforcePureArtwork(scene)
        for token in coreTokens(locked) where !result.contains(token) {
            result = "\(token)，\(result)"
        }
        return collapseSeparators(result)
    }

    func coreTokens(_ core: String) -> [String] {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        return locked
            .split { "，,、；; /｜|".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    func preservesCore(_ core: String, in scene: String) -> Bool {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        guard !locked.isEmpty else { return true }
        let text = enforcePureArtwork(scene)
        if text.contains(locked) { return true }
        let tokens = coreTokens(locked)
        return !tokens.isEmpty && tokens.allSatisfy(text.contains)
    }

    private func collapseSeparators(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: #"\s*[，,;；]\s*"#, with: "，", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[，,]{2,}"#, with: "，", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "，,；; "))
    }

    private func visualSubject(idea: String, channel: InspirationChannel?, baseline: String) -> String {
        if let typed = usableVisual(idea) { return typed }
        if let locked = usableVisual(channel?.lockedCore ?? "") { return locked }
        if let essence = usableVisual(channel?.essence ?? "") { return essence }
        let cleanBaseline = enforcePureArtwork(baseline)
        if !cleanBaseline.isEmpty, !containsInstructionLeak(cleanBaseline) { return cleanBaseline }
        return "开阔的风景"
    }

    func negativePrompt(draft: PromptDraft, channel: InspirationChannel?, model: String = "") -> String {
        var extras = [
            draft.negative,
            draft.mode == .inspiration ? channel?.exclude ?? "" : ""
        ]
        let core = [draft.input, channel?.lockedCore ?? "", channel?.essence ?? ""].joined(separator: " ")
        if hasTextRisk(core) {
            extras.append("board lettering, chalkboard writing, menu text, shop sign writing")
        }
        if ImagePromptDialect.infer(from: model) == .llada {
            // Official demo uses an empty negative. Kitchen-sink text/fog/blur
            // bans fight a model trained to render text and follow photo sentences.
            extras.append("desktop screenshot, dock, menu bar")
            var slim = extras
                .flatMap { $0.split(whereSeparator: { "、,，;；/".contains($0) }) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if allowsVisibleFigure(draft.input)
                || allowsVisibleFigure(channel?.lockedCore ?? "")
                || allowsVisibleFigure(channel?.essence ?? "") {
                slim = stripFigureBans(slim)
            }
            return Array(NSOrderedSet(array: slim).compactMap { $0 as? String }).joined(separator: ", ")
        }
        var merged = (Self.baseNegatives + extras)
            .flatMap { $0.split(whereSeparator: { "、,，;；/".contains($0) }) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if allowsVisibleFigure(draft.input)
            || allowsVisibleFigure(channel?.lockedCore ?? "")
            || allowsVisibleFigure(channel?.essence ?? "") {
            merged = stripFigureBans(merged)
        }
        return Array(NSOrderedSet(array: merged).compactMap { $0 as? String }).joined(separator: ", ")
    }

    func withVisualVariation(_ prompt: String, cue: String) -> String {
        let scene = sanitizeVisualPrompt(prompt)
        let extra = containsCJK(scene) ? sanitizeVisualPrompt(cue) : spokenHint(cue)
        guard !extra.isEmpty else { return scene }
        if scene.localizedCaseInsensitiveContains(extra) { return scene }
        return containsCJK(scene) ? scene + "，" + extra : collapseEnglish(scene + ", " + extra)
    }

    private func variationHint(_ variation: Double) -> String {
        if variation < 0.34 { return "同一地点的安静氛围" }
        if variation > 0.7 { return "更大的空间尺度，换一个角度看" }
        return ""
    }

    func needsGroundedScene(_ idea: String) -> Bool {
        isMoodTheme(idea)
    }

    /// Mood sentence stays a mood theme even after Agent/Qwen appends a person or a yard.
    /// Named subjects (上海 / 橘猫 / 宇宙) still win.
    func isMoodTheme(_ idea: String) -> Bool {
        let text = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard Self.moodOnlyKeys.contains(where: { text.localizedCaseInsensitiveContains($0) }) else { return false }
        if isBareThemeLabel(text) { return false }
        return !hasNamedIdentity(text)
    }

    private func hasNamedIdentity(_ idea: String) -> Bool {
        var residual = idea
        let fillers = Self.moodOnlyKeys
            + Self.figureSubjectKeys
            + Self.moodLandingKeys
            + Self.shotLanguageKeys
            + Self.moodPoseFillers
        for key in fillers.sorted(by: { $0.count > $1.count }) {
            residual = residual.replacingOccurrences(of: key, with: " ", options: .caseInsensitive)
        }
        return hasConcreteSubject(residual)
    }

    func hasConcretePlace(_ idea: String) -> Bool {
        hasConcreteSubject(idea)
    }

    func hasConcreteSubject(_ idea: String) -> Bool {
        let text = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if isFigureSubject(text) { return true }
        if Self.subjectKeys.contains(where: { text.localizedCaseInsensitiveContains($0) }) { return true }
        return hasResidualSubject(text)
    }

    /// Anything left after stripping mood and shot language counts as a subject.
    /// "温暖的橘猫" is a cat. "温暖的午后，电影感，85mm" is still mood-only.
    private func hasResidualSubject(_ idea: String) -> Bool {
        residualSubjectText(idea).count >= 2
    }

    private func residualSubjectText(_ idea: String) -> String {
        var residual = idea
        for key in (Self.moodOnlyKeys + Self.shotLanguageKeys).sorted(by: { $0.count > $1.count }) {
            residual = residual.replacingOccurrences(of: key, with: " ", options: .caseInsensitive)
        }
        for particle in ["的", "了", "着", "和", "与", "在", "里", "中", "很", "也", "还", "就", "是", "有", "一", "片"] {
            residual = residual.replacingOccurrences(of: particle, with: " ")
        }
        for particle in [" a ", " an ", " the ", " and ", " in ", " of ", " with ", " to "] {
            residual = residual.replacingOccurrences(of: particle, with: " ", options: .caseInsensitive)
        }
        return String(String.UnicodeScalarView(residual.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || (0x4E00...0x9FFF).contains(scalar.value)
        }))
    }

    func keepShotLanguage(_ text: String) -> String {
        var kept: [String] = []
        for key in Self.shotLanguageKeys.sorted(by: { $0.count > $1.count }) {
            guard text.localizedCaseInsensitiveContains(key) else { continue }
            if kept.contains(where: { $0.localizedCaseInsensitiveContains(key) }) { continue }
            kept.append(key)
        }
        return kept.joined(separator: "，")
    }

    func groundIfNeeded(_ scene: String, core: String, seed: Int) -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        let body = stripUnrequestedGlyphCarriers(enforcePureArtwork(scene), core: locked)
        guard needsGroundedScene(locked) else { return body }
        let remainder = collapseSeparators(body.replacingOccurrences(of: locked, with: " "))
        if hasConcretePlace(remainder), !isUnsafeMoodRemainder(remainder) {
            return body
        }
        let grounded = moodSightingChinese(seed: seed)
        let shot = keepShotLanguage(remainder)
        return pinCore(locked, onto: shot.isEmpty ? grounded : "\(grounded)，\(shot)")
    }

    func isUnsafeMoodRemainder(_ text: String) -> Bool {
        Self.streetShopResidue.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func groundedEmptyScene(seed: Int) -> String {
        moodSightingChinese(seed: seed)
    }

    func moodSightingKind(seed: Int) -> String {
        Self.moodSightingKinds[abs(seed) % Self.moodSightingKinds.count]
    }

    func moodSightingChinese(seed: Int) -> String {
        Self.moodSightingScenes[abs(seed) % Self.moodSightingScenes.count]
    }

    func moodSightingEnglish(seed: Int) -> String {
        Self.moodSightingScenesEN[abs(seed) % Self.moodSightingScenesEN.count]
    }

    /// Once a series has a short locked core, Agent expansions must not steal it.
    /// User typing a new short subject still replaces the core.
    func shouldAdoptTypedIdeaAsSeriesCore(locked: String, idea: String) -> Bool {
        let locked = locked.trimmingCharacters(in: .whitespacesAndNewlines)
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { return false }
        if locked.isEmpty || isSchemaPlaceholder(locked) { return true }
        if idea == locked { return true }
        if containsInstructionLeak(idea) { return false }
        if idea.count > max(locked.count + 80, 160) { return false }
        if idea.localizedCaseInsensitiveContains(locked), idea.count > locked.count { return false }
        if needsGroundedScene(locked), isFigureSubject(idea), !isBareThemeLabel(idea) {
            return false
        }
        return true
    }

    func allowsVisibleFigure(_ idea: String) -> Bool {
        isFigureSubject(idea) || needsGroundedScene(idea)
    }

    func stripFigureBans(_ values: [String]) -> [String] {
        values.filter { value in
            let compact = value.replacingOccurrences(of: " ", with: "")
            return !["人物", "人像", "人", "people", "person", "human"].contains(compact.lowercased())
        }
    }

    func stripUnrequestedGlyphCarriers(_ scene: String, core: String) -> String {
        var result = scene
        for phrase in Self.glyphCarriers {
            if core.localizedCaseInsensitiveContains(phrase) { continue }
            result = result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        return collapseSeparators(result)
    }

    func translateToImageEnglish(_ text: String) -> String {
        var result = text
        for (zh, en) in Self.zhToEn {
            guard !zh.isEmpty else { continue }
            result = result.replacingOccurrences(of: zh, with: en.isEmpty ? " " : " \(en) ")
        }
        return collapseEnglish(stripCJK(result))
    }

    func fallbackEnglishScene(core: String, seed: Int) -> String {
        if isFigureSubject(core) {
            return "a person in soft natural light, softly blurred background"
        }
        if needsGroundedScene(core) {
            return [
                translateToImageEnglish(core),
                moodSightingEnglish(seed: seed)
            ].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let subject = translateToImageEnglish(core)
        if subject.localizedCaseInsensitiveContains("sea") || subject.localizedCaseInsensitiveContains("maldives") || subject.localizedCaseInsensitiveContains("coast") {
            return "\(subject), open coastline, empty wet sand, wide horizon"
        }
        if subject.localizedCaseInsensitiveContains("shanghai") || subject.localizedCaseInsensitiveContains("city") {
            return "\(subject), wet riverside, empty streets, plain glass facades, reflections on dark pavement"
        }
        if !subject.isEmpty {
            if Self.subjectKeys.contains(where: { core.localizedCaseInsensitiveContains($0) }) {
                return "\(subject), open scenery, soft natural light"
            }
            return "\(subject), natural light"
        }
        return "a close-up still life, the object fills the frame"
    }

    func isStillLifeObject(_ text: String) -> Bool {
        Self.stillLifeKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func stripCJK(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            !((0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value))
        })
    }

    private func collapseEnglish(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "，", with: ", ")
        result = result.replacingOccurrences(of: "、", with: ", ")
        result = result.replacingOccurrences(of: #"[;；]+"#, with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*,\s*"#, with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?:,\s*){2,}"#, with: ", ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: ",; "))
    }

    func isFigureSubject(_ idea: String) -> Bool {
        let text = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return Self.figureSubjectKeys.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static let figureSubjectKeys: [String] = [
        "美女", "美人", "佳人", "女神", "仙子", "帅哥", "美男", "人物", "人像", "肖像",
        "女孩", "女孩儿", "女人", "女生", "女士", "少女", "少年", "男人", "男生", "男士",
        "模特", "女主", "男主", "小姐姐", "小哥哥", "女团", "男团", "偶像",
        "portrait", "woman", "women", "girl", "boy", "lady", "beauty", "model", "person", "people"
    ]

    private func isBareThemeLabel(_ idea: String) -> Bool {
        let compact = idea.replacingOccurrences(of: " ", with: "")
        return Self.bareThemeLabels.contains(compact.lowercased()) || Self.bareThemeLabels.contains(compact)
    }

    func usableVisual(_ prompt: String) -> String? {
        let cleaned = sanitizeVisualPrompt(prompt)
        guard !cleaned.isEmpty, !containsInstructionLeak(cleaned), !isSchemaPlaceholder(cleaned) else { return nil }
        return cleaned
    }

    private func appendVisual(_ parts: inout [String], _ raw: String) {
        if let cleaned = usableVisual(raw) { parts.append(cleaned) }
    }

    private func uniqued(_ parts: [String]) -> [String] {
        var seen: Set<String> = []
        return parts.filter { seen.insert($0).inserted }
    }

    func sanitizeVisualPrompt(_ prompt: String) -> String {
        var result = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in Self.instructionClauses {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        for label in Self.visualLabels {
            result = result.replacingOccurrences(of: label, with: " ", options: .caseInsensitive)
        }
        for phrase in Self.antiTextPhrases + Self.schemaPlaceholders + Self.instructionVerbs + Self.leakMarkers {
            result = result.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        for pattern in Self.mockupTriggerPatterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        result = result.replacingOccurrences(of: Self.resolutionPattern, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n+"#, with: "，", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[#*`>_]+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "[；;]{2,}", with: "，", options: .regularExpression)
        result = result.replacingOccurrences(of: "[，,]{2,}", with: "，", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "，,；; "))
    }

    private static let bareThemeLabels: Set<String> = [
        "城市风景", "城市", "都市风景", "都会风景", "风景",
        "宇宙", "星空", "深空", "魔幻世界", "魔幻", "奇幻",
        "海岸", "海边", "自然", "室内", "人物", "人像", "美女",
        "city", "cityscape", "urban", "cosmos", "space", "fantasy", "portrait"
    ]

    private static let baseNegatives = [
        "text", "letters", "words", "typography", "caption", "title", "subtitle",
        "watermark", "logo", "signature", "ui", "gui",
        "dock", "menu bar", "taskbar", "icons", "window chrome", "desktop screenshot",
        "mockup", "bezel", "frame", "status bar", "finder", "safari",
        "macos desktop", "windows desktop", "laptop frame", "monitor bezel",
        "browser chrome", "cursor", "wallpaper mockup",
        "infographic", "poster", "documentation", "instruction manual", "spec sheet",
        "caption box", "text overlay", "subtitles", "paragraphs", "ui mockup",
        "prompt", "keywords", "aesthetic definition",
        "signage", "billboard", "neon sign", "chinese text", "english text", "letters on signs",
        "chinese characters", "kanji", "hanzi", "calligraphy", "handwriting", "graffiti",
        "words on walls", "words on paper", "writing", "glyphs", "alphabet",
        "文字", "汉字", "字母", "单词", "中文", "英文", "标题", "字幕", "说明文字", "说明书",
        "招牌", "路牌", "海报文字", "广告牌", "霓虹字", "书页",
        "水印", "徽标", "签名",
        "桌面截图", "样机", "菜单栏", "任务栏", "设备边框", "文字框", "黑底白字", "界面文案", "段落文字"
    ]

    private static let mockupTriggerPatterns = [
        #"\b(?:4k|8k|uhd|hdr)\b"#,
        #"\b(?:wallpaper|desktop|mockup|macos|osx)\b"#,
        #"mac\s*os"#,
        "壁纸",
        "样机",
        "桌面",
        "超清晰",
        "超高清",
        "高清"
    ]

    static let resolutionPattern = #"\d{3,5}\s*[x×X]\s*\d{3,5}"#

    static let schemaPlaceholders = [
        "简短系列名", "一句审美定义", "逗号分隔的不可变核心词", "逗号分隔关键词",
        "维度与选项", "主色与点缀色", "禁止元素", "不可变核心词", "审美定义"
    ]

    private static let instructionVerbs = [
        "保留主题与审美", "保留主题", "不要写", "说明书", "分辨率", "字段名", "禁止输出", "必须织进",
        "留白绘图标", "景物铺到四边", "从画面最边缘到最边缘都是风景", "横向宽幅",
        "【画面核心】", "【不可变核心】", "写着", "标语", "题字"
    ]

    static let shotLanguageKeys: [String] = [
        "电影感光影", "电影感", "低机位仰望", "低机位", "机位",
        "超广角", "广角", "长焦", "超宽构图", "超宽",
        "85mm浅景深", "85mm", "50mm", "35mm", "空气透视", "浅景深",
        "cinematic", "ultra-wide", "wide-angle", "telephoto",
        "low camera angle", "camera angle", "atmospheric perspective",
        "shallow depth of field"
    ]

    private static let glyphCarriers = [
        "霓虹字", "广告牌", "招牌", "路牌", "海报", "报纸", "书页", "字幕", "屏幕",
        "signage", "billboard", "neon sign",
        "写着", "上面写着", "上面写", "写上了", "写有"
    ]

    private static let textRiskKeys = [
        "招牌", "黑板", "菜单", "咖啡店", "咖啡馆", "海报", "广告牌", "路牌",
        "chalkboard", "blackboard", "coffee shop", "menu board",
        "signboard", "billboard", "poster", "signage", " cafe", "cafe "
    ]

    private static let nightWeatherKeys = ["夜", "午夜", "深夜", "黑夜", "夜间", "night", "midnight", "noir"]
    private static let fogWeatherKeys = ["雾", "fog", "mist", "haze"]
    private static let rainWeatherKeys = ["雨", "rain"]
    private static let aerialSubjectKeys = [
        "俯瞰", "高空", "航拍", "水上飞机", "aerial", "seaplane", "from above", "looking down"
    ]
    private static let stillLifeKeys = [
        "晶石", "水晶", "宝石", "矿石", "晶体",
        "crystal", "gemstone", "mineral", "quartz", "still life"
    ]
    private static let nightTropes = [
        "noir", "horror", "underworld", "pitch dark", "barely visible",
        "moonless", "lone silhouette", "dark silhouette", "dim alley",
        "一个剪影", "夜雾", "雾夜", "阴间", "孤影", "夜里", "夜色", "品红夜"
    ]
    private static let fogTropes = [
        "volumetric fog", "thick fog", "dense mist", "dense fog", "heavy fog",
        "foggy night", "through the fog", "in the fog",
        "一层薄雾", "薄雾", "雾吃后景", "雾吃边", "雾吃", "雾里", "海雾"
    ]
    private static let unrequestedFogHints = ["mist", "fog", "haze"]
    private static let unrequestedNightHints = ["night color", "magenta night"]
    private static let daylightClimates = [
        "clear morning daylight, open air",
        "bright midday daylight, even exposure",
        "soft overcast daylight, gentle shadows",
        "warm late-afternoon daylight",
        "indoor daylight from a large window"
    ]

    private static let moodOnlyKeys: [String] = [
        "春天", "夏天", "秋天", "冬天", "午后", "早晨", "清晨", "傍晚", "黄昏",
        "温暖", "悠闲", "慵懒", "舒适", "惬意", "春", "夏", "秋", "冬",
        "spring", "summer", "autumn", "winter", "afternoon", "morning", "leisurely", "cozy"
    ]

    private static let moodLandingKeys: [String] = [
        "阳台", "院子", "庭院", "窗边", "窗", "园", "房间", "咖啡馆", "房", "室内",
        "杯子", "毯子", "地板", "物件",
        "balcony", "courtyard", "window", "garden", "room", "interior",
        "cup", "blanket", "floor"
    ]

    private static let moodPoseFillers: [String] = [
        "sits", "sitting", "stands", "standing", "walks", "walking",
        "seated", "lying", "pose", "posed", "figure", "someone", "somebody"
    ]

    private static let subjectKeys: [String] = [
        "上海", "北京", "东京", "巴黎", "纽约", "伦敦", "香港", "杭州", "成都", "重庆", "广州", "深圳",
        "外滩", "马尔代夫", "千岛", "挪威", "峡湾", "果冻海", "环礁", "泻湖",
        "海边", "海岸", "沙滩", "灯塔", "海港", "山谷", "森林", "沙漠", "草原",
        "城市", "都会", "街景", "天际线", "都市", "巷", "街",
        "房间", "书房", "咖啡馆", "窗边", "阳台", "院子", "庭院",
        "宇宙", "星空", "深空", "银河", "行星", "月球", "星球", "星云", "超新星",
        "魔幻", "奇幻", "仙侠", "城堡",
        "晶石", "水晶", "宝石", "矿石", "晶体",
        "海", "山", "林", "岛", "湖", "河", "江", "港", "桥", "塔", "寺", "店", "馆",
        "房", "园", "树", "窗", "灯", "路",
        "tokyo", "paris", "london", "shanghai", "beijing", "new york", "hong kong",
        "city", "street", "beach", "mountain", "forest", "garden", "room",
        "ocean", "sea", "lagoon", "fjord", "island", "coast", "harbor", "valley",
        "cosmos", "space", "galaxy", "nebula", "orbit", "planet", "fantasy", "castle",
        "balcony", "courtyard", "window"
    ]

    private static let moodSightingKinds = [
        "an empty place, no person",
        "one person in the light",
        "a still life, no person",
        "an interior corner"
    ]

    private static let moodSightingScenes = [
        "空着的院子，干净木地板上有一片春光，远处只有新叶",
        "光里有一个人，人只占一处",
        "近处只有杯子和毯子，没有人，光切在物件上",
        "室内一角，窗光切进来"
    ]

    private static let englishDistinguishExtras = [
        "closer to the ground",
        "more open sky",
        "warmer side light",
        "thinner mist"
    ]

    private static let moodSightingScenesEN = [
        "empty courtyard, sunlit wooden floorboards, only new leaves in the distance",
        "a person in the light, only one figure in the frame",
        "only a cup and a blanket close to the camera, no person, light on the objects",
        "an interior corner, window light cutting in"
    ]

    /// Longest phrases first. Unknown leftover CJK is stripped, never sent to the image model.
    private static let zhToEn: [(String, String)] = [
        ("温暖的春天的悠闲午后", "a warm leisurely spring afternoon"),
        ("空着的院子，干净木地板上有一片春光，远处只有新叶", "empty courtyard, sunlit wooden floorboards, only new leaves in the distance"),
        ("光里有一个人，人只占一处", "a person in the light, only one figure in the frame"),
        ("近处只有杯子和毯子，没有人，光切在物件上", "only a cup and a blanket close to the camera, no person, light on the objects"),
        ("室内一角，窗光切进来", "an interior corner, window light cutting in"),
        ("无人的阳台，竹椅空着，窗帘被风轻轻掀开一点", "empty balcony, vacant bamboo chair, curtains lifted by a breeze"),
        ("安静的窗边，一杯放下的茶还冒着热气，外面只有浅色树影", "quiet window side, a steaming cup of tea, pale tree shadows outside"),
        ("铺着毯子的地板，阳光切成一块暖色", "a blanket on the floor, a slab of warm sunlight"),
        ("从水上飞机高空俯瞰地面，马尔代夫", "turquoise Maldives atolls seen from a seaplane"),
        ("从水上飞机高空俯瞰地面", "islands and clear water seen from a seaplane"),
        ("一个咖啡店门口有一个黑板", "a cafe entrance with a chalkboard"),
        ("水上飞机", "seaplane"),
        ("高空俯瞰", "aerial view"),
        ("俯瞰地面", "aerial land and sea"),
        ("咖啡店门口", "cafe entrance"),
        ("马尔代夫的果冻海", "Maldives jelly-blue lagoon"),
        ("一杯咖啡", "a cup of coffee"),
        ("机械键盘", "mechanical keyboard"),
        ("红色跑车", "red sports car"),
        ("橘猫", "orange tabby cat"),
        ("晶石", "a crystal mineral"),
        ("水晶石", "a quartz crystal"),
        ("矿石", "a mineral ore"),
        ("晶体", "a crystal"),
        ("宝石", "a gemstone"),
        ("水晶", "quartz crystal"),
        ("超级无敌峡湾地貌", "dramatic fjord landscape"),
        ("雨夜的未来上海", "rainy night in futuristic Shanghai"),
        ("潮湿、安静、有巨大空间感的未来上海", "damp quiet futuristic Shanghai with huge space"),
        ("晨雾里的山谷", "valley in morning mist"),
        ("中国南方滨江都会", "southern Chinese riverside metropolis"),
        ("行人尺度的街景", "street at pedestrian scale"),
        ("超广角让地面很近", "ground close to the viewer"),
        ("千岛之国", "a nation of a thousand islands"),
        ("悠闲午后", "leisurely afternoon"),
        ("温暖的春天", "warm spring"),
        ("未来上海", "futuristic Shanghai"),
        ("果冻海", "jelly-blue lagoon"),
        ("峡湾地貌", "fjord landscape"),
        ("安静、空旷、有探索感的宇宙场景", "quiet vast exploratory cosmos"),
        ("宇宙场景", "cosmos"),
        ("超新星爆发", "supernova"),
        ("宇宙的起源", "the origin of the cosmos"),
        ("孤独宇宙", "solitary cosmos"),
        ("星空", "starry sky"),
        ("深空", "deep space"),
        ("银河", "galaxy"),
        ("行星", "planet"),
        ("月球", "the moon"),
        ("宇宙", "cosmos"),
        ("城市风景", "city landscape"),
        ("雨后街巷", "alleys just after rain"),
        ("干净木地板", "clean wooden floorboards"),
        ("浅色树影", "pale tree shadows"),
        ("春光", "spring sunlight"),
        ("新叶", "new leaves"),
        ("空着的院子", "empty courtyard"),
        ("无人的阳台", "empty balcony"),
        ("竹椅空着", "vacant bamboo chair"),
        ("窗帘", "curtains"),
        ("木地板", "wooden floorboards"),
        ("俯瞰", "aerial view"),
        ("高空", "from high above"),
        ("飞机", "airplane"),
        ("黑板", "chalkboard"),
        ("咖啡店", "cafe"),
        ("马尔代夫", "Maldives"),
        ("未来", "futuristic"),
        ("上海", "Shanghai"),
        ("北京", "Beijing"),
        ("东京", "Tokyo"),
        ("巴黎", "Paris"),
        ("纽约", "New York"),
        ("伦敦", "London"),
        ("香港", "Hong Kong"),
        ("杭州", "Hangzhou"),
        ("成都", "Chengdu"),
        ("重庆", "Chongqing"),
        ("广州", "Guangzhou"),
        ("深圳", "Shenzhen"),
        ("外滩", "the Bund"),
        ("挪威", "Norway"),
        ("千岛", "thousand islands"),
        ("环礁", "atoll"),
        ("泻湖", "lagoon"),
        ("峡湾", "fjord"),
        ("海边", "seaside"),
        ("海岸", "coast"),
        ("沙滩", "beach"),
        ("灯塔", "lighthouse"),
        ("海港", "harbor"),
        ("山谷", "valley"),
        ("森林", "forest"),
        ("沙漠", "desert"),
        ("草原", "grassland"),
        ("城市", "city"),
        ("都会", "metropolis"),
        ("街景", "street view"),
        ("天际线", "skyline"),
        ("都市", "city"),
        ("房间", "room"),
        ("书房", "study"),
        ("咖啡馆", "cafe"),
        ("窗边", "by the window"),
        ("阳台", "balcony"),
        ("院子", "courtyard"),
        ("庭院", "courtyard"),
        ("雨夜", "rainy night"),
        ("雨后", "after rain"),
        ("薄雾", "thin mist"),
        ("晨雾", "morning mist"),
        ("黄昏", "dusk"),
        ("黎明", "dawn"),
        ("清晨", "early morning"),
        ("午后", "afternoon"),
        ("早晨", "morning"),
        ("夜晚", "night"),
        ("深夜", "late night"),
        ("春天", "spring"),
        ("夏天", "summer"),
        ("秋天", "autumn"),
        ("冬天", "winter"),
        ("温暖", "warm"),
        ("悠闲", "leisurely"),
        ("安静", "quiet"),
        ("潮湿", "damp"),
        ("孤独", "solitary"),
        ("空旷", "open and empty"),
        ("柔和", "soft"),
        ("辽阔", "vast"),
        ("开阔", "open"),
        ("风景", "landscape"),
        ("电影感光影", "cinematic light"),
        ("低机位", "low camera angle"),
        ("超广角", "ultra-wide"),
        ("超宽构图", "ultra-wide composition"),
        ("空气透视", "atmospheric perspective"),
        ("浅景深", "shallow depth of field"),
        ("电影感", "cinematic"),
        ("机位", "camera angle"),
        ("广角", "wide-angle"),
        ("长焦", "telephoto"),
        ("超宽", "ultra-wide"),
        ("跑车", "sports car"),
        ("咖啡", "coffee"),
        ("键盘", "keyboard"),
        ("相机", "a camera"),
        ("杯子", "a cup"),
        ("猫", "cat"),
        ("狗", "dog"),
        ("美女", "a beautiful woman"),
        ("人像", "portrait of a person"),
        ("人物", "a person"),
        ("半身", "half-body"),
        ("逆光", "backlit"),
        ("柔光", "soft light"),
        ("侧光", "side light"),
        ("阳光", "sunlight"),
        ("春", "spring"),
        ("夏", "summer"),
        ("秋", "autumn"),
        ("冬", "winter"),
        ("雨", "rain"),
        ("雾", "mist"),
        ("雪", "snow"),
        ("海", "sea"),
        ("山", "mountain"),
        ("林", "woods"),
        ("岛", "island"),
        ("湖", "lake"),
        ("河", "river"),
        ("江", "river"),
        ("港", "harbor"),
        ("桥", "bridge"),
        ("树", "trees"),
        ("窗", "window"),
        ("光", "light"),
        ("风", "wind"),
        ("夜", "night"),
        ("的", ""),
        ("了", ""),
        ("着", ""),
        ("和", ""),
        ("与", ""),
        ("在", ""),
        ("里", ""),
        ("中", ""),
        ("很", ""),
        ("也", ""),
        ("还", ""),
        ("就", ""),
        ("是", ""),
        ("有", ""),
        ("一", ""),
        ("片", ""),
        ("只有", "only"),
        ("远处", "in the distance")
    ].sorted { $0.0.count > $1.0.count }

    private static let streetShopResidue = [
        "巷", "街", "店", "铺", "欢迎", "光临", "广告", "海报", "招牌", "路牌"
    ]

    private static let antiTextPhrases = [
        "没有文字", "不要文字", "无文字", "不含文字", "不要出现文字", "杜绝文字",
        "无水印", "没有水印", "不要水印",
        "no text", "without text", "no letters", "no typography", "no watermark",
        "无文字水印"
    ]

    private static let leakMarkers = [
        "用户原始想法", "原初想法", "原始想法", "本地约束草稿", "约束草稿",
        "灵感频道", "频道审美", "必须包含", "禁止出现", "配色：", "色板：",
        "构图留白", "目标屏幕", "参考图片", "不可变核心词", "可变维度规则",
        "本次变化种子", "Prompt 策略", "纯画面硬性要求", "避免：", "避免:",
        "没有文字", "no text", "Dock", "菜单栏",
        "简短系列名", "一句审美定义", "逗号分隔", "不可变核心", "画面核心", "维度与选项",
        "保留主题", "不要写", "说明书", "分辨率", "字段名", "禁止输出", "必须织进",
        "those characters", "subject name", "keep them in the output", "the user wrote",
        "core subject", "light for this frame"
    ]

    private static let instructionEchoPhrases = [
        "this frame differs by",
        "this frame differs",
        "frame differs by",
        "differs by",
        "those characters are the subject name",
        "those characters",
        "keep them in the output",
        "keep the subject's name",
        "do not translate the name away",
        "the user wrote",
        "core subject (keep this name, do not swap it)",
        "core subject",
        "light for this frame",
        "write a short wide-frame image prompt",
        "write a short photograph",
        "continues to the edges",
        "not a handheld snapshot",
        "not a poster with a border",
        "not a centered product photo",
        "describe what fills the screen",
        "do not invent lettering or logos",
        "use even daylight and natural color",
        "do not default to night",
        "这一张多看见：",
        "这一张多看见",
        "看见轮换，不要整批女人，不要整批空院子",
        "看见轮换",
        "不要整批女人",
        "不要整批空院子",
        "就是这个主题，不要改成别的东西",
        "就是这个主题",
        "这是人，人留在画面里",
        "板面空白",
        "深色空板",
        "画面里是人",
        "主题：",
        "光：",
        "看：",
        "看见：",
        "气味：",
        "还要看见：",
        "颜色："
    ]

    private static let visualLabels = [
        "配色：", "色板：", "不可变内核：", "允许变化维度：", "必须包含：", "禁止出现：",
        "灵感频道：", "频道审美：", "用户原始想法：", "原初想法：", "原始想法：",
        "本地约束草稿：", "约束草稿：", "构图留白：", "目标屏幕：", "参考图片：",
        "不可变核心词：", "可变维度规则：", "本次变化种子：", "Prompt 策略：",
        "这一张必须走到的画面组合：", "候选差异指令：", "本次变化："
    ]

    private static let instructionClauses = [
        #"(?:用户原始想法|原初想法|原始想法)\s*[：:“”"'][^\n]*"#,
        #"(?:本地约束草稿|约束草稿)\s*[：:]\s*[^\n]*"#,
        #"(?:灵感频道|频道审美|必须包含|禁止出现|色板|配色|构图留白|目标屏幕|参考图片|不可变核心词|可变维度规则|本次变化种子|Prompt 策略)\s*[：:]\s*[^\n]*"#,
        "纯画面硬性要求：[^；;\\n]*",
        "避免：[^；;\\n]*",
        "候选差异指令：[^；;\\n]*",
        "本次变化：[^；;\\n]*",
        "用户原始想法：[^；;\\n]*",
        "本地约束草稿：[^；;\\n]*",
        "这一张必须走到的画面组合：[^；;\\n]*",
        #"\(no dock[^)]*\)"#
    ]
}
