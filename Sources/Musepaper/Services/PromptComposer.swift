import Foundation

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
    func imageModelPrompt(_ scene: String, core: String = "", seed: Int = 0) -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        let incoming = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = groundIfNeeded(incoming.isEmpty ? locked : incoming, core: locked, seed: seed)
        body = stripUnrequestedGlyphCarriers(enforcePureArtwork(body), core: locked)
        if needsGroundedScene(locked) {
            var english = containsCJK(body) ? translateToImageEnglish(body) : collapseEnglish(body)
            if english.split(whereSeparator: { $0.isWhitespace || $0 == "," }).count < 4 {
                english = fallbackEnglishScene(core: locked, seed: seed)
            }
            if !hasConcreteSubject(english) {
                english = collapseEnglish([english, moodSightingEnglish(seed: seed)].filter { !$0.isEmpty }.joined(separator: ", "))
            }
            return wrapImagePrompt(collapseEnglish(stripCJK(english)), core: locked)
        }
        body = pinCore(locked, onto: body)
        guard !body.isEmpty else { return wrapImagePrompt(locked, core: locked) }
        return wrapImagePrompt(body, core: locked)
    }

    private func wrapImagePrompt(_ body: String, core: String) -> String {
        let text = collapseEnglish(body)
        guard !text.isEmpty else {
            return isFigureSubject(core) ? "photorealistic photograph of a person" : "photorealistic photograph"
        }
        if isFigureSubject(core) {
            return collapseEnglish("photorealistic portrait photograph, \(text)")
        }
        if text.localizedCaseInsensitiveContains("photorealistic photograph") {
            return text
        }
        return collapseEnglish("photorealistic photograph, \(text)")
    }

    /// Library / Agent rewrite. Named subjects keep the user's name.
    /// Mood-only cores become a spoken English sighting, not a fixed empty yard.
    func spokenRewrite(_ scene: String, core: String, seed: Int = 0) -> String {
        let locked = usableVisual(core) ?? sanitizeVisualPrompt(core)
        var body = stripUnrequestedGlyphCarriers(enforcePureArtwork(scene), core: locked)
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

    func negativePrompt(draft: PromptDraft, channel: InspirationChannel?) -> String {
        let extras = [
            draft.negative,
            draft.mode == .inspiration ? channel?.exclude ?? "" : ""
        ]
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
        if hasResidualSubject(core) {
            return "the given subject, natural light, cinematic framing"
        }
        return "clear subject in natural light"
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
        "signage", "billboard", "neon sign"
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
        ("马尔代夫的果冻海", "Maldives jelly-blue lagoon"),
        ("一杯咖啡", "a cup of coffee"),
        ("机械键盘", "mechanical keyboard"),
        ("红色跑车", "red sports car"),
        ("橘猫", "orange tabby cat"),
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
        "保留主题", "不要写", "说明书", "分辨率", "字段名", "禁止输出", "必须织进"
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
