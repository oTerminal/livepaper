import Foundation

/// What a Workshop shader says about itself in comments: `// [COMBO] {...}` lines and the JSON after
/// each uniform (`uniform float g_Scale; // {"material":"scale","default":1}`).
public struct ShaderAnnotations {
    public struct Combo {
        public let name: String
        public let defaultValue: Int
        public let json: [String: Any]
    }

    public struct Uniform {
        public let type: String
        public let name: String
        public let arrayCount: Int?
        public let json: [String: Any]?
        public var materialKey: String? { json?["material"] as? String }
        public var defaultValue: Any? { json?["default"] }
    }

    public var combos: [Combo] = []
    public var uniforms: [String: Uniform] = [:]
    public var uniformOrder: [String] = []
    /// Declared but switched off by its author (`[COMBO_OFF]`, `[OFF_COMBO]`): left undefined.
    public var disabledCombos: [String] = []
    public var badJSON: [String] = []

    public init() {}

    public init(sources: [String]) {
        for source in sources { parse(source) }
    }

    static let comboRegex = try! NSRegularExpression(pattern: #"^\s*//\s*\[(\w+)\]\s*(\{.*\})\s*$"#)
    static let uniformRegex = try! NSRegularExpression(
        pattern: #"^\s*uniform\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*(?:\[\s*(\d+)\s*\])?\s*;\s*(?://\s*(.*))?$"#)

    mutating func parse(_ source: String) {
        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let s = String(line)
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = Self.comboRegex.firstMatch(in: s, range: range) {
                let tag = ns.substring(with: m.range(at: 1))
                let body = ns.substring(with: m.range(at: 2))
                guard let json = Self.json(body) else { badJSON.append(s); continue }
                let name = json["combo"] as? String ?? "?"
                if tag == "COMBO" {
                    let value = (json["default"] as? NSNumber)?.intValue ?? 0
                    if !combos.contains(where: { $0.name == name }) {
                        combos.append(Combo(name: name, defaultValue: value, json: json))
                    }
                } else {
                    disabledCombos.append(name)
                }
                continue
            }
            if let m = Self.uniformRegex.firstMatch(in: s, range: range) {
                let type = ns.substring(with: m.range(at: 1))
                let name = ns.substring(with: m.range(at: 2))
                let count = m.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 3)))
                var json: [String: Any]?
                if m.range(at: 4).location != NSNotFound {
                    let comment = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
                    if comment.hasPrefix("{") {
                        json = Self.json(comment)
                        if json == nil { badJSON.append(s) }
                    }
                }
                if uniforms[name] == nil { uniformOrder.append(name) }
                // A later declaration with an annotation wins over a bare one (vertex vs fragment).
                if uniforms[name]?.json == nil || json != nil {
                    uniforms[name] = Uniform(type: type, name: name, arrayCount: count, json: json)
                }
            }
        }
    }

    static let leadingZero = try! NSRegularExpression(pattern: #"(?<![\d.])0+(\d)"#)

    static func json(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return obj }
        // Authors write what Wallpaper Engine's parser accepts, e.g. "range":[0,01]. Drop leading zeros and retry.
        let ns = text as NSString
        let fixed = leadingZero.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
        return (try? JSONSerialization.jsonObject(with: Data(fixed.utf8))) as? [String: Any]
    }

    /// Texture slots whose presence switches a combo on: `uniform sampler2D g_Texture1; // {"combo":"MASK"}`.
    public var textureCombos: [(slot: Int, combo: String)] {
        uniforms.values.compactMap { u in
            guard u.type.hasPrefix("sampler"), let combo = u.json?["combo"] as? String,
                  let slot = Self.textureSlot(u.name) else { return nil }
            return (slot, combo)
        }
    }

    public static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture") else { return nil }
        return Int(name.dropFirst("g_Texture".count))
    }

    /// The preprocessor defines for one program: the shader's [COMBO] defaults, then 1 or 0 for each
    /// texture-switched combo, then the material's and the scene's explicit combos. Sorted by name.
    public func defines(explicit: [String: Int], boundSlots: Set<Int>) -> [(String, Int)] {
        var combos: [String: Int] = [:]
        for c in self.combos { combos[c.name] = c.defaultValue }
        for (slot, combo) in textureCombos { combos[combo] = boundSlots.contains(slot) ? 1 : 0 }
        for (k, v) in explicit { combos[k] = v }
        return combos.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
