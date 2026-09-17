// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// Everything that touches WallpaperExtensionKit's private types. Adapted from
// Phosphene's RuntimeHelpers.swift, SnapshotCreation.swift, CodableShims.swift and
// SettingsProvider.swift (MIT, (c) 2026 kageroumado). See Spikes/NOTICE.

import AppKit
import Foundation
import IOSurface

enum PrivateBridge {
    static let frameworkPath = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"

    /// The classes WallpaperAgent may send or expect back. NSXPC refuses any class
    /// that is not whitelisted per selector.
    static let payloadClassNames = [
        "WallpaperIDXPC", "WallpaperCreationRequestXPC", "WallpaperUpdateRequestXPC",
        "WallpaperRemoteContextXPC", "WallpaperSnapshotXPC", "WallpaperContentTypeSetXPC",
        "WallpaperChoiceIDXPC", "WallpaperChoiceIDsXPC", "WallpaperExtensionChoiceRequestXPC",
        "WallpaperChoiceRequestAdditionResultXPC", "WallpaperDebugRequestXPC",
        "WallpaperDebugResponseXPC", "WallpaperMigrationVersionXPC",
        "WallpaperSettingsViewModelsXPC", "AuditTokenXPC",
    ]

    /// Launch self-check: one log line that says whether this macOS still has the
    /// private layout the extension depends on.
    static func load() -> Bool {
        guard dlopen(frameworkPath, RTLD_LAZY) != nil else {
            spikeLog("bridge: dlopen failed: \(String(cString: dlerror()))")
            return false
        }
        let missing = payloadClassNames.filter { objc_getClass($0) == nil }
        spikeLog(missing.isEmpty
            ? "bridge: WallpaperExtensionKit loaded, all \(payloadClassNames.count) payload classes present"
            : "bridge: MISSING classes: \(missing.joined(separator: ", "))")
        return missing.isEmpty
    }

    /// The reply to `acquire`: a WallpaperRemoteContextXPC whose `box` ivar holds the
    /// CAContext id as a UInt32.
    static func remoteContextReply(contextID: UInt32) -> AnyObject? {
        guard let cls = objc_getClass("WallpaperRemoteContextXPC") as? AnyClass,
              let instance = class_createInstance(cls, 0) else { return nil }
        let object = instance as AnyObject
        let offset = class_getInstanceVariable(cls, "box").map(ivar_getOffset) ?? 8
        // A changed layout must fail closed, not write past the instance.
        guard offset >= 0, offset + MemoryLayout<UInt32>.size <= class_getInstanceSize(cls) else {
            spikeLog("bridge: WallpaperRemoteContextXPC layout unexpected (offset \(offset), size \(class_getInstanceSize(cls)))")
            return nil
        }
        Unmanaged.passUnretained(object).toOpaque().advanced(by: offset).storeBytes(of: contextID, as: UInt32.self)
        return object
    }

    /// The reply to `snapshot`: a WallpaperSnapshotXPC wrapping an IOSurface. The
    /// agent shows it while no live context is hosted, which is what keeps the lock
    /// transition from going grey (S6).
    static func snapshotReply(colour: CGColor, frame: IOSurface? = nil, width: Int = 1920, height: Int = 1080) -> AnyObject? {
        guard let cls = objc_getClass("WallpaperSnapshotXPC") as? AnyClass,
              let instance = class_createInstance(cls, 0) else { return nil }
        let offset = 8
        guard offset + MemoryLayout<UnsafeRawPointer>.size <= class_getInstanceSize(cls) else {
            spikeLog("bridge: WallpaperSnapshotXPC layout unexpected (size \(class_getInstanceSize(cls)))")
            return nil
        }
        guard let surface = frame ?? solidSurface(colour: colour, width: width, height: height) else { return nil }
        let object = instance as AnyObject
        let retained = Unmanaged.passRetained(surface).toOpaque()
        Unmanaged.passUnretained(object).toOpaque().advanced(by: offset).storeBytes(of: UnsafeRawPointer(retained), as: UnsafeRawPointer.self)
        return object
    }

    private static func solidSurface(colour: CGColor, width: Int, height: Int) -> IOSurface? {
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width, .height: height, .bytesPerElement: 4, .pixelFormat: 0x4247_5241, // 'BGRA'
        ]
        guard let surface = IOSurface(properties: properties) else { return nil }
        surface.lock(options: [], seed: nil)
        if let context = CGContext(
            data: surface.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: surface.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.setFillColor(colour)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        surface.unlock(options: [], seed: nil)
        return surface
    }

    /// One group with one item, "Livepaper": the roadmap's single entry that the user
    /// picks once.
    static func settingsViewModels(bundleID: String, thumbnail: URL) -> AnyObject? {
        let identifier = "livepaper"
        let choiceID = ChoiceID(id: identifier, descriptor: ChoiceIDDescriptor(
            provider: ChoiceProviderID(rawValue: bundleID), identifier: identifier, files: [], configuration: Data(identifier.utf8)))
        let item = SettingsItem(
            id: choiceID, localizedName: "Livepaper", thumbnail: .image(url: thumbnail),
            choice: ChoiceDescriptor(
                id: choiceID, provider: ChoiceProviderID(rawValue: bundleID), identifier: identifier, name: "Livepaper",
                localizedDescription: "Your live wallpaper", thumbnail: .image(url: thumbnail), isDownloaded: true, options: []),
            contentBadge: .video, showInTopLevel: true, sortOrder: 0, disposability: .none, contextMenu: nil)
        let group = SettingsGroup(
            id: GroupID(id: "livepaper"), items: [item], localizedName: "Livepaper", disposability: .none, sortOrder: -100,
            sortID: GroupSortID(id: "com.apple.wallpaper.aerials"), allChoiceID: nil, shouldHideItemLabels: false,
            contextMenu: nil, thumbnail: nil)
        let model = SettingsViewModel(groups: [group], refreshPolicy: .default, isModificationDisabled: false)
        return remap(SettingsViewModels(desktop: model, screenSaver: model))
    }

    /// Archives our shim and decodes it back as the private class. Secure coding has to
    /// be off for the class substitution; the archive never leaves this function.
    private static func remap(_ models: SettingsViewModels) -> AnyObject? {
        guard let real = objc_getClass("WallpaperSettingsViewModelsXPC") as? AnyClass,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: ShimViewModelsXPC(models), requiringSecureCoding: false),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(real, forClassName: "ShimViewModelsXPC")
        let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        if let error = unarchiver.error { spikeLog("bridge: view model remap failed: \(error)") }
        unarchiver.finishDecoding()
        return result as AnyObject?
    }

    /// The tile image, written once into the container.
    static func thumbnailURL() -> URL? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/livepaper-tile.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let image = NSImage(size: NSSize(width: 480, height: 270), flipped: false) { rect in
            NSColor(cgColor: SurfaceLayers.spikeColour)?.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? png.write(to: url)) == nil ? nil : url
    }
}

// MARK: - Request field extraction

/// The XPC payloads are Swift structs boxed in ObjC classes; their stored properties
/// are only reachable by reflection.
func mirrorFind(_ label: String, in value: Any, depth: Int = 0) -> Any? {
    guard depth < 8 else { return nil }
    for child in Mirror(reflecting: value).children {
        if child.label == label { return child.value }
        if let found = mirrorFind(label, in: child.value, depth: depth + 1) { return found }
    }
    return nil
}

func mirrorFindUUID(in value: Any, depth: Int = 0) -> UUID? {
    guard depth < 8 else { return nil }
    if let uuid = value as? UUID { return uuid }
    for child in Mirror(reflecting: value).children {
        if let found = mirrorFindUUID(in: child.value, depth: depth + 1) { return found }
    }
    return nil
}

func enumCaseName(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .enum, let label = mirror.children.first?.label { return label }
    return String(describing: value)
}

// MARK: - Codable shims
//
// These mirror the Codable layout of the private WallpaperTypes structs closely enough
// that the real decoder accepts them. Only the cases the spike uses are modelled.

struct SettingsViewModels: Codable { var desktop: SettingsViewModel?; var screenSaver: SettingsViewModel? }
struct SettingsViewModel: Codable { var groups: [SettingsGroup]; var refreshPolicy: RefreshPolicy; var isModificationDisabled: Bool }
struct GroupID: Codable { var id: String }
struct GroupSortID: Codable { var id: String }
struct ChoiceID: Codable { var id: String; var descriptor: ChoiceIDDescriptor }
struct ChoiceIDDescriptor: Codable { var provider: ChoiceProviderID; var identifier: String; var files: [URL]; var configuration: Data }
struct ContextMenu: Codable { var items: [String] }

struct SettingsGroup: Codable {
    var id: GroupID
    var items: [SettingsItem]
    var localizedName: String
    var disposability: Disposability
    var sortOrder: Int
    var sortID: GroupSortID?
    var allChoiceID: ChoiceID?
    var shouldHideItemLabels: Bool?
    var contextMenu: ContextMenu?
    var thumbnail: Data?
}

struct SettingsItem: Codable {
    var id: ChoiceID
    var localizedName: String
    var thumbnail: Thumbnail
    var choice: ChoiceDescriptor
    var contentBadge: ContentBadge
    var showInTopLevel: Bool
    var sortOrder: Int
    var disposability: Disposability
    var contextMenu: ContextMenu?
}

struct ChoiceDescriptor: Codable {
    var id: ChoiceID
    var provider: ChoiceProviderID
    var identifier: String
    var name: String?
    var localizedDescription: String
    var thumbnail: Thumbnail
    var isDownloaded: Bool
    var options: [String]
}

struct ChoiceProviderID: Codable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Swift encodes a payload-less enum case as `{"caseName": {}}`; these shims must too.
protocol CaseOnlyShim: Codable, RawRepresentable where RawValue == String {}
extension CaseOnlyShim {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let key = container.allKeys.first, let value = Self(rawValue: key.stringValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown case"))
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        _ = container.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(rawValue))
    }
}

enum Disposability: String, CaseOnlyShim { case none, removable, purgeable }
enum ContentBadge: String, CaseOnlyShim { case none, video, dynamic }
enum RefreshPolicy: String, CaseOnlyShim { case `default` }

enum Thumbnail: Codable {
    case image(url: URL)

    private enum Keys: String, CodingKey { case image }
    private enum ImageKeys: String, CodingKey { case url }

    init(from decoder: any Decoder) throws {
        let nested = try decoder.container(keyedBy: Keys.self).nestedContainer(keyedBy: ImageKeys.self, forKey: .image)
        self = .image(url: try nested.decode(URL.self, forKey: .url))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        var nested = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .image)
        if case let .image(url) = self { try nested.encode(url, forKey: .url) }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Encodes under the key the real WallpaperSettingsViewModelsXPC reads.
@objc(ShimViewModelsXPC)
final class ShimViewModelsXPC: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true
    let value: SettingsViewModels

    init(_ value: SettingsViewModels) { self.value = value }
    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        do {
            try (coder as? NSKeyedArchiver)?.encodeEncodable(value, forKey: "WallpaperSettingsViewModels")
        } catch {
            spikeLog("bridge: view model encode failed: \(error)")
        }
    }
}
