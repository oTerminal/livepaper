import Foundation

/// Values in scene and material JSON come as numbers, "x y z" strings, arrays, or wrapped in an object:
/// `{"value": ..., "user": ...}` (bound to a user property), `{"value": ..., "script": ...}`,
/// `{"value": ..., "animation": ...}`. S9 takes the stored value in every case.
public enum JSONValue {
    public static func unwrap(_ any: Any?) -> Any? {
        if let dict = any as? [String: Any] {
            if let v = dict["value"] { return unwrap(v) }
            return nil
        }
        if any is NSNull { return nil }
        return any
    }

    public static func floats(_ any: Any?) -> [Float]? {
        switch unwrap(any) {
        case let n as NSNumber: return [n.floatValue]
        case let s as String:
            let parts = s.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Float($0) }
            return parts.isEmpty ? nil : parts
        case let a as [Any]: return a.compactMap { ($0 as? NSNumber)?.floatValue }
        default: return nil
        }
    }

    public static func float(_ any: Any?, _ fallback: Float) -> Float { floats(any)?.first ?? fallback }

    public static func vec3(_ any: Any?, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
        guard let f = floats(any), !f.isEmpty else { return fallback }
        if f.count == 1 { return SIMD3(repeating: f[0]) }
        return SIMD3(f[0], f.count > 1 ? f[1] : fallback.y, f.count > 2 ? f[2] : fallback.z)
    }

    public static func bool(_ any: Any?, _ fallback: Bool) -> Bool {
        switch unwrap(any) {
        case let n as NSNumber: return n.boolValue
        case let s as String: return s == "true" || s == "1"
        default: return fallback
        }
    }

    public static func int(_ any: Any?) -> Int? { (unwrap(any) as? NSNumber)?.intValue }
}
