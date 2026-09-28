import Foundation

/// What the metrics lines say of each wallpaper: its largest presented gap and
/// whether that was at a seam, and its gaps over `limit` split
/// at-seam and mid-pass. A gap at a seam is the engine's; mid-pass at 60 fps,
/// load (S2.md).
public struct WallpaperGaps: Equatable, Sendable {
    /// `PresentedGaps.limit` in the engine (LivepaperPlayback): 1.5 frame durations.
    public static let limit = 1.5

    public struct Wallpaper: Equatable, Sendable {
        /// The optimised copy's folder: for a library video, the wallpaper's ID.
        public var folder: String
        public var loops: Int
        public var largest: Double?
        public var isLargestAtSeam: Bool
        public var overLimitAtSeams: Int
        public var overLimitMidPass: Int

        public init(folder: String, loops: Int, largest: Double?, isLargestAtSeam: Bool, overLimitAtSeams: Int, overLimitMidPass: Int) {
            self.folder = folder
            self.loops = loops
            self.largest = largest
            self.isLargestAtSeam = isLargestAtSeam
            self.overLimitAtSeams = overLimitAtSeams
            self.overLimitMidPass = overLimitMidPass
        }
    }

    public private(set) var wallpapers: [Wallpaper] = []

    /// An engine's numbers run from its start on a video, so each run's last line
    /// holds its counts; a line with no more loops than the one before is a new run.
    public init(_ lines: [MetricsLine]) {
        var runs: [String: [MetricsLine]] = [:]
        var finals: [MetricsLine] = []
        for line in lines {
            let engine = "\(line.surface ?? "preview") \(line.folder)"
            if let last = runs[engine]?.last, line.loops <= last.loops { finals.append(last) }
            runs[engine, default: []].append(line)
            if let last = runs[engine]?.last, last.loops < line.loops { runs[engine] = [line] }
        }
        finals += runs.values.compactMap(\.last)

        var byFolder: [String: Wallpaper] = [:]
        for line in finals {
            var wallpaper = byFolder[line.folder]
                ?? Wallpaper(folder: line.folder, loops: 0, largest: nil, isLargestAtSeam: false, overLimitAtSeams: 0, overLimitMidPass: 0)
            wallpaper.loops += line.loops
            wallpaper.overLimitAtSeams += line.gapsOverLimitAtSeams
            wallpaper.overLimitMidPass += line.gapsOverLimitElsewhere
            byFolder[line.folder] = wallpaper
        }
        // The largest gap is the largest any line saw, whichever run it was in.
        for line in lines {
            guard let gap = line.largestPresentedGap, gap > byFolder[line.folder]?.largest ?? -1 else { continue }
            byFolder[line.folder]?.largest = gap
            byFolder[line.folder]?.isLargestAtSeam = line.largestPresentedGapAtSeam == gap
        }
        wallpapers = byFolder.values.sorted { $0.folder < $1.folder }
    }
}
