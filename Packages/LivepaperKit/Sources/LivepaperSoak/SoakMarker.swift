import Foundation

/// A row of the soak's `events.csv`: what `soak.sh` did (`sleep`, `displaysleep`,
/// `lock`) or what a person marked before doing it (`lid`, `replug`, `fus`).
/// Times in the report come from the log; a marker only says what caused the next event.
public struct SoakMarker: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case start
        case sleep
        case displaySleep = "displaysleep"
        case lock
        case lid
        case replug
        case fastUserSwitch = "fus"
        case note
        case end
    }

    public var time: Date
    public var kind: Kind
    public var note: String

    public init(time: Date, kind: Kind, note: String = "") {
        self.time = time
        self.kind = kind
        self.note = note
    }

    /// `events.csv`, `time,kind,note`, in time order; a row that does not read is counted.
    public static func read(csv: String) -> (markers: [SoakMarker], unreadRows: Int) {
        var markers: [SoakMarker] = []
        var unread = 0
        for row in CSV.rows(csv, header: "time,kind,note") {
            guard row.count >= 2, let time = Timestamp.date(row[0]), let kind = Kind(rawValue: String(row[1])) else {
                unread += 1
                continue
            }
            markers.append(SoakMarker(time: time, kind: kind, note: row.dropFirst(2).joined(separator: ",")))
        }
        return (markers.sorted { $0.time < $1.time }, unread)
    }
}
