import Foundation

struct VariationLayer: Equatable, Sendable {
    var key: String
    var name: String
    var value: String
    var visual: String
}

struct VariationCombo: Equatable, Sendable {
    var themeKey: String
    var layers: [VariationLayer]

    var visualPhrase: String {
        layers.map(\.visual).filter { !$0.isEmpty }.joined(separator: "，")
    }

    func value(for key: String) -> String? {
        layers.first { $0.key == key }?.value
    }
}

struct VariationPlanner: Sendable {
    static var catalogSize: Int { extraCatalog.count + 4 }
    private static var extraCatalog: [Axis] { Theme.sharedCraft }

    func plan(idea: String, count: Int, seed: Int, customAxes: String = "") -> [VariationCombo] {
        let n = InspirationChannel.clampedCount(count)
        let theme = Theme.detect(from: idea)
        let core = mergedAxes(theme: theme, idea: idea, customAxes: customAxes)
        var combos = (0..<n).map { slot -> VariationCombo in
            let extras = pickExtraAxes(theme: theme, seed: seed &* 17 &+ slot &* 101, take: 4)
            return selectCombo(axes: core + extras, themeKey: theme.rawValue, slot: slot, seed: seed)
        }
        spread(axisKey: AxisKey.place, in: &combos, axes: core)
        spread(axisKey: AxisKey.shot, in: &combos, axes: core)
        spread(axisKey: AxisKey.sighting, in: &combos, axes: core)
        uniquify(&combos, axes: core)
        return combos
    }

    func cue(from rules: String, seed: Int) -> String {
        plan(idea: "", count: 1, seed: seed, customAxes: rules)[0].visualPhrase
    }

    func explore(seed: Int, pick: Int) -> [String] {
        pickExtraAxes(theme: .generic, seed: seed, take: pick).map { axis in
            let option = axis.options[abs(seed) % max(axis.options.count, 1)]
            return option.visual
        }
    }

    func exploreBatch(count: Int, seed: Int) -> [[String]] {
        (0..<InspirationChannel.clampedCount(count)).map { slot in
            explore(seed: seed &+ slot &* 97, pick: 8)
        }
    }

    struct CatalogEntry: Equatable, Sendable {
        var name: String
    }

    static var catalog: [CatalogEntry] {
        extraCatalog.map { CatalogEntry(name: $0.name) }
    }

    var availableAxisCount: Int { Self.catalogSize }

    private func mergedAxes(theme: Theme, idea: String, customAxes: String) -> [Axis] {
        var axes = theme.axes(placeLocked: ideaLocksPlace(idea))
        for parsed in parseAxes(customAxes) {
            guard let key = classify(name: parsed.name, values: parsed.options.map(\.value)) else {
                axes.append(parsed)
                continue
            }
            if key == AxisKey.place, ideaLocksPlace(idea) { continue }
            if let index = axes.firstIndex(where: { $0.key == key }) {
                axes[index].options = uniqued(parsed.options + axes[index].options)
            } else {
                axes.append(Axis(key: key, name: parsed.name, options: parsed.options))
            }
        }
        return axes.filter { !$0.options.isEmpty }
    }

    private func selectCombo(axes: [Axis], themeKey: String, slot: Int, seed: Int) -> VariationCombo {
        let layers = axes.enumerated().map { index, axis -> VariationLayer in
            let count = max(axis.options.count, 1)
            let pick: Int
            if [AxisKey.place, AxisKey.shot, AxisKey.climate, AxisKey.lens, AxisKey.sighting].contains(axis.key) {
                let offset = abs(seed &* (19 &+ index &* 11)) % count
                pick = (offset + slot) % count
            } else {
                pick = abs(seed &* (19 &+ index &* 11) &+ slot &* 29) % count
            }
            let option = axis.options[pick]
            return VariationLayer(key: axis.key, name: axis.name, value: option.value, visual: option.visual)
        }
        return VariationCombo(themeKey: themeKey, layers: layers)
    }

    private func pickExtraAxes(theme: Theme, seed: Int, take: Int) -> [Axis] {
        let catalog = Self.extraCatalog.filter { $0.fits(theme) }
        guard !catalog.isEmpty else { return [] }
        var order = Array(catalog.indices)
        var state = seed == 0 ? 1 : seed
        for i in stride(from: order.count - 1, through: 1, by: -1) {
            state = state &* 1_103_515_245 &+ 12_345
            order.swapAt(i, abs(state) % (i + 1))
        }
        let count = min(max(take, 3), order.count)
        return order.prefix(count).map { catalog[$0] }
    }

    private func spread(axisKey: String, in combos: inout [VariationCombo], axes: [Axis]) {
        guard let axis = axes.first(where: { $0.key == axisKey }), axis.options.count >= 2 else { return }
        let needed = min(2, combos.count, axis.options.count)
        var used = Set(combos.compactMap { $0.value(for: axisKey) })
        guard used.count < needed else { return }
        for index in combos.indices where used.count < needed {
            let option = axis.options[index % axis.options.count]
            guard !used.contains(option.value) else { continue }
            replace(axisKey, with: option, in: &combos[index])
            used.insert(option.value)
        }
    }

    private func uniquify(_ combos: inout [VariationCombo], axes: [Axis]) {
        let extras = [
            Option(value: "近前景遮挡", visual: "最近一层切开画面，后面的层次退开"),
            Option(value: "更远地平线", visual: "地平线压得很低，大面积天空或水域铺开"),
            Option(value: "侧面光路", visual: "主光从画面一侧扫过，影子又长又清楚"),
            Option(value: "更低视平线", visual: "视平线贴近地面，主体显得更高")
        ]
        var seen: Set<String> = []
        for index in combos.indices {
            var phrase = combos[index].visualPhrase
            var extraIndex = 0
            while seen.contains(phrase) {
                let extra = extras[(index + extraIndex) % extras.count]
                if let lens = axes.first(where: { $0.key == AxisKey.lens }) {
                    let option = lens.options[(index + extraIndex + 1) % lens.options.count]
                    replace(AxisKey.lens, with: option, in: &combos[index])
                } else {
                    combos[index].layers.append(
                        VariationLayer(key: "extra", name: "层次", value: extra.value, visual: extra.visual)
                    )
                }
                phrase = combos[index].visualPhrase
                extraIndex += 1
                if extraIndex > extras.count { break }
            }
            seen.insert(phrase)
        }
    }

    private func replace(_ key: String, with option: Option, in combo: inout VariationCombo) {
        if let layerIndex = combo.layers.firstIndex(where: { $0.key == key }) {
            combo.layers[layerIndex].value = option.value
            combo.layers[layerIndex].visual = option.visual
        }
    }

    private func parseAxes(_ rules: String) -> [Axis] {
        rules
            .split(whereSeparator: { "；;\n".contains($0) })
            .compactMap { group -> Axis? in
                let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0 == "：" || $0 == ":" }).map(String.init)
                guard parts.count == 2 else { return nil }
                let values = parts[1]
                    .split(whereSeparator: { "/、,，|".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !values.isEmpty else { return nil }
                let options = values.map { Option(value: $0, visual: Self.visualMap[$0] ?? "\(parts[0])走到\($0)这一档") }
                return Axis(key: parts[0], name: parts[0], options: options)
            }
    }

    private func classify(name: String, values: [String]) -> String? {
        if name.contains("地点") || name.contains("城市") || name.contains("地貌") || name.contains("天体") {
            return AxisKey.place
        }
        if name.contains("景别") || name.contains("观察") { return AxisKey.shot }
        if name.contains("天气") || name.contains("气候") || name.contains("时段") || name.contains("天文") {
            return AxisKey.climate
        }
        if name.contains("镜头") || name.contains("光线") || name.contains("机位") { return AxisKey.lens }
        if name.contains("看见") || name.contains("目击") { return AxisKey.sighting }
        if name.contains("视角") || name.contains("构图") {
            if values.contains(where: { $0.contains("街") || $0.contains("天际") || $0.contains("航拍") || $0.contains("室内") }) {
                return AxisKey.shot
            }
            return AxisKey.lens
        }
        return nil
    }

    private func ideaLocksPlace(_ idea: String) -> Bool {
        let text = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.namedPlaces.contains(where: { text.localizedCaseInsensitiveContains($0) }) { return true }
        if ["峡湾", "fjord", "环礁", "泻湖", "果冻海", "千岛"].contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        return text.count >= 6 && !Theme.isBareLabel(text)
    }

    private func uniqued(_ options: [Option]) -> [Option] {
        var seen: Set<String> = []
        return options.filter { seen.insert($0.value).inserted }
    }

    private enum AxisKey {
        static let place = "place"
        static let shot = "shot"
        static let climate = "climate"
        static let lens = "lens"
        static let sighting = "sighting"
    }

    private struct Axis {
        var key: String
        var name: String
        var options: [Option]

        func fits(_ theme: Theme) -> Bool {
            if Theme.urbanCraftKeys.contains(key) {
                return theme == .city || theme == .interior
            }
            if theme == .portrait {
                return Self.portraitCraftKeys.contains(key)
            }
            return true
        }

        private static let portraitCraftKeys: Set<String> = [
            "kelvin", "mood", "focus", "material", "air", "season", "palette-accent", "motion", "era"
        ]
    }

    private struct Option {
        var value: String
        var visual: String
    }

    private enum Theme: String {
        case city, cosmos, fantasy, coast, nature, interior, portrait, mood, generic

        static func detect(from idea: String) -> Theme {
            let text = idea.lowercased()
            if PromptComposer().isMoodTheme(idea) {
                return .mood
            }
            let figureKeys = [
                "美女", "美人", "佳人", "女神", "仙子", "帅哥", "美男", "人物", "人像", "肖像",
                "女孩", "女人", "女生", "女士", "少女", "少年", "男人", "男生", "男士",
                "模特", "女主", "男主", "小姐姐", "小哥哥", "女团", "男团", "偶像",
                "portrait", "woman", "women", "girl", "boy", "lady", "beauty", "model", "person", "people"
            ]
            if matches(text, figureKeys) {
                return .portrait
            }
            if matches(text, ["宇宙", "星空", "深空", "银河", "行星", "月球", "orbit", "galaxy", "nebula", "cosmos", "space"]) {
                return .cosmos
            }
            if matches(text, ["魔幻", "奇幻", "仙侠", "城堡", "浮空", "金龙", "神龙", "巨龙", "飞龙", "五爪", "麒麟", "貔貅", "神兽", "凤凰", "fantasy", "castle", "dragon", "phoenix"]) {
                return .fantasy
            }
            if matches(text, ["室内", "房间", "书房", "咖啡馆", "窗边", "interior", "apartment"]) {
                return .interior
            }
            if matches(text, ["峡湾", "fjord", "槽谷", "冰川", "雪峰"]) {
                return .nature
            }
            if matches(text, ["马尔代夫", "环礁", "泻湖", "果冻海", "海岸", "海边", "沙滩", "灯塔", "海港", "coast", "beach", "lighthouse", "harbor"]) {
                return .coast
            }
            if matches(text, ["城市", "都会", "街景", "天际线", "都市", "city", "skyline", "street", "urban"]) {
                return .city
            }
            if matches(text, ["山", "谷", "林", "森", "沙漠", "草原", "湖", "mountain", "forest", "desert", "valley"]) {
                return .nature
            }
            return .generic
        }

        static func isBareLabel(_ idea: String) -> Bool {
            let compact = idea.replacingOccurrences(of: " ", with: "")
            return ["城市风景", "城市", "都市风景", "风景", "宇宙", "星空", "深空", "魔幻世界", "魔幻", "海岸", "海边", "自然", "室内", "人物", "人像", "美女", "city", "cityscape", "urban", "cosmos", "space", "fantasy", "portrait"].contains(compact.lowercased())
        }

        private static func matches(_ text: String, _ keys: [String]) -> Bool {
            keys.contains { text.localizedCaseInsensitiveContains($0) }
        }

        func axes(placeLocked: Bool) -> [Axis] {
            core(placeLocked: placeLocked)
        }

        private func core(placeLocked: Bool) -> [Axis] {
            switch self {
            case .city:
                return [
                    Axis(key: AxisKey.place, name: "地点", options: placeLocked ? Self.cityLockedPlaces : Self.cityPlaces),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.cityShots),
                    Axis(key: AxisKey.climate, name: "气候", options: Self.cityClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.cityLenses)
                ]
            case .cosmos:
                return [
                    Axis(key: AxisKey.place, name: "位置", options: Self.cosmosPlaces),
                    Axis(key: AxisKey.shot, name: "观察点", options: Self.cosmosShots),
                    Axis(key: AxisKey.climate, name: "天文", options: Self.cosmosClimates),
                    Axis(key: AxisKey.lens, name: "尺度", options: Self.cosmosLenses)
                ]
            case .fantasy:
                return [
                    Axis(key: AxisKey.place, name: "地貌", options: Self.fantasyPlaces),
                    Axis(key: AxisKey.shot, name: "尺度", options: Self.fantasyShots),
                    Axis(key: AxisKey.climate, name: "天候", options: Self.fantasyClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.fantasyLenses)
                ]
            case .coast:
                return [
                    Axis(key: AxisKey.place, name: "岸线", options: placeLocked ? Self.coastLockedPlaces : Self.coastPlaces),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.coastShots),
                    Axis(key: AxisKey.climate, name: "海况", options: Self.coastClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.coastLenses)
                ]
            case .nature:
                return [
                    Axis(key: AxisKey.place, name: "地貌", options: placeLocked ? Self.natureLockedPlaces : Self.naturePlaces),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.natureShots),
                    Axis(key: AxisKey.climate, name: "气候", options: Self.natureClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.natureLenses)
                ]
            case .interior:
                return [
                    Axis(key: AxisKey.place, name: "房间", options: Self.interiorPlaces),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.interiorShots),
                    Axis(key: AxisKey.climate, name: "窗光", options: Self.interiorClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.interiorLenses)
                ]
            case .portrait:
                return [
                    Axis(key: AxisKey.place, name: "场景", options: Self.portraitPlaces),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.portraitShots),
                    Axis(key: AxisKey.climate, name: "光线", options: Self.portraitClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.portraitLenses)
                ]
            case .mood:
                return [
                    Axis(key: AxisKey.sighting, name: "看见什么", options: Self.moodSightings),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.genericShots),
                    Axis(key: AxisKey.climate, name: "气候", options: Self.genericClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.genericLenses)
                ]
            case .generic:
                return [
                    Axis(key: AxisKey.place, name: "地点", options: placeLocked ? Self.genericLockedPlaces : Self.genericPlaces),
                    Axis(key: AxisKey.shot, name: "景别", options: Self.genericShots),
                    Axis(key: AxisKey.climate, name: "气候", options: Self.genericClimates),
                    Axis(key: AxisKey.lens, name: "镜头", options: Self.genericLenses)
                ]
            }
        }

        fileprivate static let urbanCraftKeys: Set<String> = []

        fileprivate static let sharedCraft: [Axis] = [
            Axis(key: "season", name: "物候", options: [
                Option(value: "春芽", visual: "颜色还浅，空气偏冷而干净"),
                Option(value: "盛夏", visual: "热浪让远景发虚"),
                Option(value: "秋色", visual: "整幅偏暖，饱和度被压低"),
                Option(value: "初雪", visual: "高光变硬，阴影更干净")
            ]),
            Axis(key: "air", name: "空气", options: [
                Option(value: "水汽", visual: "空气饱含水汽，远景发乳"),
                Option(value: "尘埃光柱", visual: "空气里能看见一条光柱"),
                Option(value: "薄雾", visual: "薄雾贴着表面走，后景退淡"),
                Option(value: "雨丝", visual: "斜划的雨丝让空气有方向")
            ]),
            Axis(key: "ground", name: "地面反光", options: [
                Option(value: "强倒影", visual: "地面把天空的颜色倒过来"),
                Option(value: "弱反光", visual: "地面只留很弱的冷光"),
                Option(value: "碎镜", visual: "地面碎成许多小块反光"),
                Option(value: "哑光", visual: "地面吸光，几乎没有倒影")
            ]),
            Axis(key: "kelvin", name: "色温", options: [
                Option(value: "冷青", visual: "整幅偏冷青，只有一点暖"),
                Option(value: "琥珀", visual: "琥珀暖调从一侧漫过来"),
                Option(value: "品红夜", visual: "夜色带品红，亮部是冷的"),
                Option(value: "灰绿", visual: "灰绿色压住饱和度")
            ]),
            Axis(key: "material", name: "表面质感", options: [
                Option(value: "高反光", visual: "表面叠着多层倒影"),
                Option(value: "粗颗粒", visual: "近处表面颗粒很粗"),
                Option(value: "吸色", visual: "表面把颜色吸进去"),
                Option(value: "水渍", visual: "表面留着深浅不一的水渍")
            ]),
            Axis(key: "depth", name: "纵深", options: [
                Option(value: "三层", visual: "前中后三层都站得住"),
                Option(value: "薄景", visual: "几乎只有一层薄景"),
                Option(value: "雾吃后景", visual: "后景被雾吃掉，只剩近处"),
                Option(value: "隧道", visual: "空间像一条纵深隧道")
            ]),
            Axis(key: "density", name: "疏密", options: [
                Option(value: "左密右疏", visual: "左边堆细节，右边空出来"),
                Option(value: "中空", visual: "中间空、四周实"),
                Option(value: "近压远空", visual: "近处压迫，远处突然空"),
                Option(value: "下半幅", visual: "细节都堆在下半幅")
            ]),
            Axis(key: "motion", name: "动势", options: [
                Option(value: "静止", visual: "完全静止，像时间被按住"),
                Option(value: "长曝光", visual: "亮部被拉成淡淡的痕迹"),
                Option(value: "微动", visual: "只有最浅的一层在动"),
                Option(value: "风速", visual: "空气被风拉斜，近处仍稳")
            ]),
            Axis(key: "scale", name: "尺度", options: [
                Option(value: "人眼近", visual: "空间按站在里面的尺度展开"),
                Option(value: "巨大", visual: "主体大到边缘都裁不住"),
                Option(value: "远小", visual: "主体只占画面很小一块"),
                Option(value: "压顶", visual: "上沿压得很近，空间变矮")
            ]),
            Axis(key: "era", name: "时间感", options: [
                Option(value: "陈旧", visual: "颜色发旧，边缘被时间磨软"),
                Option(value: "干净现代", visual: "线条硬，颜色克制"),
                Option(value: "未来", visual: "体量更大，光更冷"),
                Option(value: "褪色", visual: "像一张褪了色的旧片子")
            ]),
            Axis(key: "water", name: "水面", options: [
                Option(value: "贴边", visual: "水面贴着主体的边缘走"),
                Option(value: "压低", visual: "水面压得很低，留出大面积空间"),
                Option(value: "干燥", visual: "完全干燥，没有反光"),
                Option(value: "铺开", visual: "水面宽得像把地面换成一层镜子")
            ]),
            Axis(key: "plants", name: "覆盖", options: [
                Option(value: "厚覆盖", visual: "表面被一层厚绿或厚暗盖住"),
                Option(value: "一点覆盖", visual: "只有很少的一点覆盖色"),
                Option(value: "从缝里", visual: "覆盖色只从缝里冒出来"),
                Option(value: "裸露", visual: "几乎没有覆盖，结构直接露着")
            ]),
            Axis(key: "lamps", name: "人造光", options: [
                Option(value: "一点暖", visual: "暗部里只有一点暖光"),
                Option(value: "冷阵列", visual: "冷白光排成很克制的阵列"),
                Option(value: "无灯", visual: "完全没有人造光"),
                Option(value: "扫光", visual: "一束扫过的光切开雾")
            ]),
            Axis(key: "mood", name: "情绪", options: [
                Option(value: "空寂", visual: "空寂，像刚被时间按住"),
                Option(value: "将雨", visual: "将雨的压迫感压在头顶"),
                Option(value: "过后", visual: "热闹过后的安静"),
                Option(value: "倦怠", visual: "午后的倦怠，影子很长")
            ]),
            Axis(key: "focus", name: "焦点", options: [
                Option(value: "中景实", visual: "只实中景，远景化开"),
                Option(value: "全域", visual: "从近到远都咬得很清楚"),
                Option(value: "浅景深", visual: "浅景深贴着最近的一层"),
                Option(value: "超焦距", visual: "超焦距把最远一层也咬住")
            ]),
            Axis(key: "geometry", name: "几何", options: [
                Option(value: "消失点", visual: "空间收向唯一的消失点"),
                Option(value: "对称倒影", visual: "水面把画面完全对折"),
                Option(value: "对角", visual: "一道对角线切开明暗"),
                Option(value: "套层", visual: "近处的边缘再套一层景")
            ]),
            Axis(key: "blocks", name: "色块", options: [
                Option(value: "暗里一点暖", visual: "大面积暗部里只有一点暖"),
                Option(value: "冷暖对半", visual: "冷暖从中间劈成两半"),
                Option(value: "高键", visual: "浅色高键，暗部很少"),
                Option(value: "亮带", visual: "中间一条亮带，上下都暗")
            ]),
            Axis(key: "timewear", name: "痕迹", options: [
                Option(value: "雨痕", visual: "地面还留着浅浅的雨痕"),
                Option(value: "风化", visual: "表面被年头磨出底层"),
                Option(value: "未完成", visual: "边缘还留着未完成的茬"),
                Option(value: "淡印", visual: "只有很淡的使用痕迹")
            ]),
            Axis(key: "edge", name: "边缘", options: [
                Option(value: "压暗", visual: "四周轻轻压暗"),
                Option(value: "一侧过亮", visual: "一侧被晨光过亮"),
                Option(value: "雾吃边", visual: "雾把左右边缘吃掉"),
                Option(value: "重暗角", visual: "暗角很重，像镜头本身")
            ]),
            Axis(key: "horizon", name: "地平线", options: [
                Option(value: "低天大", visual: "地平线很低，天空占大半"),
                Option(value: "高地铺", visual: "地平线很高，地面铺开"),
                Option(value: "微倾", visual: "地平线微微倾斜"),
                Option(value: "看不见天", visual: "上沿被挡住，几乎看不见天")
            ]),
            Axis(key: "sound", name: "声景", options: [
                Option(value: "回声", visual: "空旷得像有回声"),
                Option(value: "远静", visual: "远处极静，近处也没有动静"),
                Option(value: "刚过去", visual: "像有什么刚过去，空气还没平"),
                Option(value: "压低", visual: "所有声音都被压到最低")
            ]),
            Axis(key: "symbol", name: "辨识", options: [
                Option(value: "轮廓", visual: "远处只剩一个淡轮廓"),
                Option(value: "倒影", visual: "倒影比实物更清楚"),
                Option(value: "无标志", visual: "完全没有可辨认的标志"),
                Option(value: "剪影", visual: "主体收成剪影，只留边缘光")
            ]),
            Axis(key: "wind", name: "风", options: [
                Option(value: "无风", visual: "没有风，所有边缘都停着"),
                Option(value: "侧风", visual: "侧风把水纹和雾拉斜"),
                Option(value: "大风", visual: "大风让云走得很快，近处稳"),
                Option(value: "穿堂", visual: "风从纵深里穿过去")
            ]),
            Axis(key: "crowd", name: "人迹", options: [
                Option(value: "无人", visual: "看不见任何人"),
                Option(value: "远影", visual: "极远处只有一个模糊人影"),
                Option(value: "空位", visual: "近处留着一个空着的尺度"),
                Option(value: "刚离开", visual: "像刚有人离开，空气还没收回来")
            ]),
            Axis(key: "sky", name: "天空", options: [
                Option(value: "层云", visual: "低层云像天花板"),
                Option(value: "碎云", visual: "碎云把光切成块"),
                Option(value: "无云", visual: "天空干净得几乎没有层次"),
                Option(value: "夜空", visual: "夜空深，只有很少的星")
            ]),
            Axis(key: "palette-accent", name: "点缀色", options: [
                Option(value: "一点红", visual: "整幅里只有一点红"),
                Option(value: "一点金", visual: "暗部里嵌一点金"),
                Option(value: "一点青", visual: "暖调里嵌一点青"),
                Option(value: "无点缀", visual: "没有跳色，全部克制")
            ])
        ]

        private static let cityPlaces = [
            Option(value: "国内滨江都会", visual: "湿润的滨江空间，水平面和垂直体量叠在一层"),
            Option(value: "国外老城街巷", visual: "挤迫的巷道空间，墙面很近，暖色往里收"),
            Option(value: "海岸都会", visual: "开阔的海湾空间，水平线拉得很长"),
            Option(value: "山地依山城市", visual: "沿坡叠上去的层状空间，雾气切出高度")
        ]
        private static let cityLockedPlaces = [
            Option(value: "近处巷道", visual: "同一座城市的近处，墙面和地面压得很近"),
            Option(value: "滨水展开", visual: "同一座城市的开阔滨水一面，倒影把上下对折"),
            Option(value: "高处叠层", visual: "同一座城市的高处，层次向后变淡"),
            Option(value: "俯瞰脉络", visual: "同一座城市的俯瞰，道路像发光的脉络")
        ]
        private static let cityShots = [
            Option(value: "街景", visual: "行人尺度，地面和近处边缘压得很近"),
            Option(value: "天际线", visual: "远景横向展开，中段是一条天际剪影"),
            Option(value: "室内望向窗外", visual: "从暗处看向亮处，边缘切开外面"),
            Option(value: "航拍", visual: "高处俯瞰，纹理同时展开"),
            Option(value: "滨水倒影", visual: "贴着水面，倒影把体量拉长")
        ]
        private static let cityClimates = [
            Option(value: "雨后", visual: "雨刚停，地面把天空的颜色倒过来"),
            Option(value: "薄雾清晨", visual: "薄雾清晨，远处只剩淡色块"),
            Option(value: "黄昏", visual: "黄昏暖金，一侧烧成一条光带"),
            Option(value: "蓝调时刻", visual: "蓝调时刻，天空比地面更深，亮部刚起")
        ]
        private static let cityLenses = [
            Option(value: "超广角", visual: "超广角让地面很近，远处向天际线收束"),
            Option(value: "长焦压缩", visual: "长焦把前后层压成密集的一层"),
            Option(value: "逆光剪影", visual: "逆光把体量收成剪影，边缘有一圈亮边"),
            Option(value: "低机位仰望", visual: "低机位仰望，上沿压向画面上方")
        ]

        private static let cosmosPlaces = [
            Option(value: "近地轨道", visual: "弯曲的行星边缘占满下半画幅"),
            Option(value: "气态巨行星近旁", visual: "巨大球体压过来，条纹云带很近"),
            Option(value: "荒芜卫星表面", visual: "地面一直铺到弯曲的地平线"),
            Option(value: "星云内部", visual: "发光气体包住视线，远近都在雾里")
        ]
        private static let cosmosShots = [
            Option(value: "舷窗框景", visual: "近处边缘切开外面的深空"),
            Option(value: "行星全景", visual: "球体和远处光带同时成立"),
            Option(value: "近景结构", visual: "最近一层占满前景，后面虚开"),
            Option(value: "星系远望", visual: "极远，只有稀疏光点和一道光带")
        ]
        private static let cosmosClimates = [
            Option(value: "日蚀阴影", visual: "日蚀阴影里，日冕成一圈冷白火"),
            Option(value: "恒星黎明", visual: "恒星从边缘升起，辉光被拉成一条弧"),
            Option(value: "永夜星海", visual: "没有晨昏，只有密集星海和深黑"),
            Option(value: "极光带", visual: "极光带像薄纱贴着大气层")
        ]
        private static let cosmosLenses = [
            Option(value: "超广角畸变", visual: "超广角让近处弯曲，远处仍保持完整"),
            Option(value: "长焦压缩星环", visual: "长焦把多层光环压成紧密的光带"),
            Option(value: "逆光日冕", visual: "逆光里只剩发光的边缘"),
            Option(value: "微距尘埃", visual: "贴近最近的一层颗粒，后面虚成光斑")
        ]

        private static let fantasyPlaces = [
            Option(value: "浮空层", visual: "层状地貌悬在云海之上"),
            Option(value: "断裂高差", visual: "很大的断裂高差，石阶通向断开的对面"),
            Option(value: "向下洞穴", visual: "向下的洞穴空间，晶体从壁上长出"),
            Option(value: "雾中垂直", visual: "雾里的垂直结构，地面被架空")
        ]
        private static let fantasyShots = [
            Option(value: "王国远景", visual: "远景里整座体量嵌在地貌中"),
            Option(value: "遗迹近景", visual: "近景占满，裂隙和表面细节很近"),
            Option(value: "峡谷俯瞰", visual: "从高处俯瞰，纵深向下去"),
            Option(value: "桥上平视", visual: "从中央平视对面的巨大体量")
        ]
        private static let fantasyClimates = [
            Option(value: "极光夜", visual: "极光夜，天空有缓慢移动的色幕"),
            Option(value: "雷暴将至", visual: "雷暴将至，云底压得很低，远处有一道电"),
            Option(value: "月蚀", visual: "月蚀红光，地面只剩暗红的轮廓"),
            Option(value: "金色尘埃黄昏", visual: "金色尘埃悬浮在黄昏里，光束能被看见")
        ]
        private static let fantasyLenses = [
            Option(value: "史诗广角", visual: "史诗广角，近处和远处同时清楚"),
            Option(value: "长焦压缩山脊", visual: "长焦把层层山脊压在一起"),
            Option(value: "逆光巨物", visual: "逆光里只剩轮廓和一圈尘埃光"),
            Option(value: "低机位仰望", visual: "低机位仰望，体量高过云层")
        ]

        private static let coastLockedPlaces = [
            Option(value: "浅层水色", visual: "同一片海的浅层，水底颜色一层层变"),
            Option(value: "沙线", visual: "同一片海的沙线被浅水托起来"),
            Option(value: "近处透明", visual: "同一片海的近处，能看见水下的纹理"),
            Option(value: "高处全岸", visual: "从高处看同一片海，岸线绕成完整一圈")
        ]
        private static let coastPlaces = [
            Option(value: "礁石岬角", visual: "破碎的礁石岸线，浪线反复叠上"),
            Option(value: "平展沙岸", visual: "平展的沙岸，水面像一层薄膜"),
            Option(value: "垂直陡岸", visual: "垂直的陡岸，海面在脚下"),
            Option(value: "湾内静水", visual: "湾内静水，水平线几乎不动")
        ]
        private static let coastShots = [
            Option(value: "岸线平视", visual: "贴着岸线平视，海平线横贯画面"),
            Option(value: "航拍海岸", visual: "航拍海岸，浪线像反复叠上的白边"),
            Option(value: "近处表层", visual: "最近一层的泡沫和反光占满前景"),
            Option(value: "暗处望海", visual: "从暗处看向亮处，边缘切出一片海")
        ]
        private static let coastClimates = [
            Option(value: "雨后清澈", visual: "雨后空气被洗过，远岸轮廓很硬"),
            Option(value: "海雾", visual: "海雾把后景吞掉，只剩近处的湿"),
            Option(value: "黄昏金海", visual: "黄昏把海面烧成一条金色道路"),
            Option(value: "风暴前夕", visual: "风暴前夕，云墙压向海面，水色发暗")
        ]
        private static let coastLenses = [
            Option(value: "超广角浪线", visual: "超广角让近处浪很大，远岸仍在画里"),
            Option(value: "长焦压缩礁石", visual: "长焦把一串岸线压成紧密的剪影"),
            Option(value: "逆光海面", visual: "逆光海面闪成碎金，体量变成剪影"),
            Option(value: "低机位湿沙", visual: "机位贴近湿沙，倒影和岸线叠在一起")
        ]

        private static let natureLockedPlaces = [
            Option(value: "近处一层", visual: "贴着同一主体的最近一层看"),
            Option(value: "开阔出口", visual: "退到同一主体的开阔一面，空间铺开"),
            Option(value: "纵深通道", visual: "顺着同一主体的纵深看进去"),
            Option(value: "高处俯瞰", visual: "从高处看清同一主体怎么组织")
        ]
        private static let naturePlaces = [
            Option(value: "深谷", visual: "深切的谷地空间，两岸夹得很紧"),
            Option(value: "覆盖海", visual: "连绵的覆盖感，表面像一层浪"),
            Option(value: "高地", visual: "开阔高地，风把空间推远"),
            Option(value: "旱原", visual: "干燥的水平延展，一直铺到地平线")
        ]
        private static let natureShots = [
            Option(value: "谷底平视", visual: "从低处平视，空间从脚下伸向深处"),
            Option(value: "山脊远望", visual: "从高处远望，层层向后变淡"),
            Option(value: "近处表层", visual: "最近一层的表面和一束光占满画面"),
            Option(value: "航拍地形", visual: "航拍，起伏像一张被光画出的地图")
        ]
        private static let natureClimates = [
            Option(value: "雨后云海", visual: "雨后云海填满低处，只有高处露出来"),
            Option(value: "晨雾", visual: "晨雾贴着地面走，形体一根根从雾里出来"),
            Option(value: "秋色黄昏", visual: "秋色黄昏，地面和天空同时偏暖"),
            Option(value: "雪后静谧", visual: "雪后静谧，声音像被吸走，只剩干净的形")
        ]
        private static let natureLenses = [
            Option(value: "广角深远", visual: "广角把近处和远处同时放进景深"),
            Option(value: "长焦层峦", visual: "长焦压缩层峦，变成一组淡色剪影"),
            Option(value: "丁达尔光", visual: "空气里的尘埃把光束变成可见的柱"),
            Option(value: "低机位", visual: "低机位贴着最近一层，后面高得不像比例")
        ]

        private static let interiorPlaces = [
            Option(value: "近楼窗光", visual: "近处窗光很硬，外面只剩一堵亮墙"),
            Option(value: "含水光", visual: "地面反着外面的水光"),
            Option(value: "暗木空间", visual: "暗的木结构空间，窗外是一层绿"),
            Option(value: "高窗竖光", visual: "高窗落下的竖向光线切开暗部")
        ]
        private static let interiorShots = [
            Option(value: "窗边中景", visual: "窗边中景，人的位置空着，只留光"),
            Option(value: "房间全景", visual: "房间全景，空间被分成几块安静的面"),
            Option(value: "门外回望", visual: "从暗的前景回望整个亮空间"),
            Option(value: "近处表层", visual: "近处表层和窗外的色温对照")
        ]
        private static let interiorClimates = [
            Option(value: "阴天漫射", visual: "阴天漫射光，影子很软，颜色偏冷"),
            Option(value: "黄昏斜光", visual: "黄昏斜光切过地面，尘埃在光里"),
            Option(value: "雨打玻璃", visual: "雨点打在透明面上，外面的景被水纹扭开"),
            Option(value: "清晨冷光", visual: "清晨冷光，墙面还没被暖起来")
        ]
        private static let interiorLenses = [
            Option(value: "35mm人文", visual: "接近站在房间里的视角和比例"),
            Option(value: "广角空间", visual: "广角把天花和地板同时拉进来"),
            Option(value: "框景", visual: "近处边缘就是画框，外面被切成一块"),
            Option(value: "浅景深", visual: "浅景深，近处清楚，外面化成色块")
        ]

        private static let moodSightings = [
            Option(value: "空场", visual: "看得见的空地方，没有人"),
            Option(value: "人", visual: "光里有一个人，人只占一处"),
            Option(value: "静物", visual: "近处只有物件和光，没有人"),
            Option(value: "室内", visual: "室内一角，窗光切进来")
        ]

        private static let portraitPlaces = [
            Option(value: "窗边柔光", visual: "人物站在窗边，侧光勾出轮廓，背景只剩淡色块"),
            Option(value: "暗调棚感", visual: "深色干净背景，人物是唯一亮部"),
            Option(value: "户外虚化", visual: "户外自然光，背景虚成柔软色斑，人物清晰"),
            Option(value: "夜景氛围", visual: "远处城市光斑虚化，人物被一束柔光托住")
        ]
        private static let portraitShots = [
            Option(value: "半身", visual: "半身构图，脸与肩是视觉中心"),
            Option(value: "近景面部", visual: "近景面部，五官细节清楚，肩线可裁切"),
            Option(value: "全身站姿", visual: "全身站姿，人物占画面主要高度，脚站得住"),
            Option(value: "过肩三分", visual: "人物偏一侧，遵循三分，目光有方向")
        ]
        private static let portraitClimates = [
            Option(value: "伦勃朗侧光", visual: "一侧主光，面颊留下三角形亮斑"),
            Option(value: "窗光漫射", visual: "大面积柔光，影子很软，皮肤过渡干净"),
            Option(value: "逆光轮廓", visual: "逆光给发丝与肩线一圈亮边，正面用弱补光"),
            Option(value: "黄金时刻", visual: "低角度暖金光，肤色偏暖，阴影拉长而软")
        ]
        private static let portraitLenses = [
            Option(value: "85mm浅景深", visual: "约八五焦段，背景明显虚化，人物分离干净"),
            Option(value: "50mm自然", visual: "接近人眼比例，透视自然，不夸张"),
            Option(value: "平视对视", visual: "机位与视线平齐，构图端正"),
            Option(value: "轻微俯视", visual: "轻微俯视，更利落，不夸张畸变")
        ]

        private static let genericLockedPlaces = [
            Option(value: "近处一层", visual: "同一主体的近处，地面和边缘占满前景"),
            Option(value: "开阔一面", visual: "同一主体的开阔一面，空间铺得很远"),
            Option(value: "纵深通道", visual: "同一主体的深处，视线顺着纵深进去"),
            Option(value: "高处全貌", visual: "从同一主体的高处看清它怎么组织")
        ]
        private static let genericPlaces = [
            Option(value: "开阔原野", visual: "开阔空间，一条亮带把画面切开"),
            Option(value: "密与疏交界", visual: "密和疏的交界，一边实一边空"),
            Option(value: "贴水展开", visual: "贴着水面展开，倒影把上下对折"),
            Option(value: "高地对着天", visual: "高处对着很大的天空，地面很薄")
        ]
        private static let genericShots = [
            Option(value: "远景建立", visual: "远景，主体只占画面一小块"),
            Option(value: "中景路径", visual: "中景，视线顺着地面伸进去"),
            Option(value: "近景表层", visual: "近景，表面占满画幅"),
            Option(value: "俯瞰全貌", visual: "轻微俯瞰，看清它怎么组织在一起")
        ]
        private static let genericClimates = [
            Option(value: "雨后", visual: "雨后地面还亮着，空气里有一层薄雾"),
            Option(value: "薄雾", visual: "薄雾把后景削成淡色的层"),
            Option(value: "黄昏", visual: "黄昏低光，长影子横过地面"),
            Option(value: "清冷早晨", visual: "清冷早晨，颜色还没被太阳烤暖")
        ]
        private static let genericLenses = [
            Option(value: "广角", visual: "广角强调空间深度"),
            Option(value: "长焦压缩", visual: "长焦把前后层压在一起"),
            Option(value: "逆光", visual: "逆光让边缘发光，中间留下暗部"),
            Option(value: "低机位", visual: "低机位让前景地面变得很大")
        ]
    }

    private static let namedPlaces = [
        "上海", "北京", "东京", "巴黎", "纽约", "伦敦", "香港", "杭州", "成都", "重庆", "广州", "深圳",
        "外滩", "灯塔", "月球", "木星", "土星", "马尔代夫", "千岛", "挪威",
        "tokyo", "paris", "london", "shanghai", "beijing", "new york", "hong kong"
    ]

    private static let visualMap: [String: String] = [
        "晴": "晴朗空气，影子边缘很硬",
        "雨": "正在下雨，雨丝和湿反光同时存在",
        "雾": "雾把远处削成淡色块",
        "雪": "落雪或积雪，高光变硬，地面变亮",
        "黎明": "黎明冷光，天空比地面更亮",
        "黄昏": "黄昏暖金，长影子横过地面",
        "深夜": "深夜，只有少量灯和很深的暗部",
        "广角": "广角强调近大远小",
        "低机位": "机位贴近地面向上看",
        "航拍": "从高处垂直或斜着俯瞰",
        "长焦": "长焦压缩前后层次"
    ]
}
