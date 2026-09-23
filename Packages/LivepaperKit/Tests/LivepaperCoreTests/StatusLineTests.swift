import Testing
import LivepaperCore

struct StatusLineTests {
    struct Line: Sendable {
        var host: RenderHostStatus
        var showing = 2
        var isPausedAll = false
        var importing: (position: Int, count: Int)?
    }

    static let rows: [Row<Line, StatusLineContent>] = [
        // Every host status.
        Row("live on two displays", Line(host: .live), .idle("Live on 2 displays")),
        Row("live on one display", Line(host: .live, showing: 1), .idle("Live on 1 display")),
        Row("live, with nothing to show", Line(host: .live, showing: 0), .idle("No wallpaper set")),
        Row("stopped by Pause All", Line(host: .stopped, isPausedAll: true), .idle("Paused")),
        Row("stopped otherwise", Line(host: .stopped), .idle("Stopped")),
        Row("Pause All reads paused before the host has stopped", Line(host: .live, isPausedAll: true), .idle("Paused")),
        Row("connecting", Line(host: .connecting), .working("Connecting to the wallpaper service")),
        Row("not selected", Line(host: .notSelected), .idle("Livepaper is not the wallpaper in System Settings")),
        Row("unavailable", Line(host: .unavailable), .idle("Not available on this version of macOS")),
        Row("recovering by flushing", Line(host: .recovering(.flush)), .working("Recovering the wallpaper")),
        Row("recovering by rebuilding the surface", Line(host: .recovering(.rebuildSurface)), .working("Recovering the wallpaper")),
        Row("recovering by rebuilding the pipeline", Line(host: .recovering(.rebuildPipeline)), .working("Recovering the wallpaper")),
        Row("waiting on a restarted service", Line(host: .recovering(.restartAgent)), .serviceNotResponding),

        // An import takes the line.
        Row("importing one of several", Line(host: .live, importing: (2, 5)), .working("Importing 2 of 5")),
        Row("importing one alone", Line(host: .live, importing: (1, 1)), .working("Importing")),
        Row("an import before connecting", Line(host: .connecting, importing: (1, 3)), .working("Importing 1 of 3")),
        Row("an import before not selected", Line(host: .notSelected, importing: (1, 3)), .working("Importing 1 of 3")),
        Row("an import during Pause All", Line(host: .stopped, isPausedAll: true, importing: (1, 3)), .working("Importing 1 of 3")),
        Row("a service not responding before an import", Line(host: .recovering(.restartAgent), importing: (1, 3)), .serviceNotResponding),
    ]

    @Test(arguments: rows)
    func `the status line says what the render host and the imports are doing`(row: Row<Line, StatusLineContent>) {
        let line = statusLine(
            host: row.input.host, showing: row.input.showing, isPausedAll: row.input.isPausedAll, importing: row.input.importing
        )

        #expect(line == row.expected)
    }
}
