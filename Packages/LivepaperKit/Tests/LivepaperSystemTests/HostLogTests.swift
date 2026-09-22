import LivepaperCore
import LivepaperSystem
import Testing

/// Other milestones read these lines, so each recovery level's wording is pinned.
struct HostLogTests {
    static let rows: [Row<String, String>] = [
        Row("silence asks for a flush", HostLog.silence(.flush), "host: no heartbeat, asking the extension to flush"),
        Row(
            "silence asks for a rebuilt surface",
            HostLog.silence(.rebuildSurface),
            "host: no heartbeat, asking the extension to rebuildSurface"
        ),
        Row("the app asks for a rebuilt pipeline", HostLog.recover(.rebuildPipeline), "host: asking the extension to rebuildPipeline"),
        Row("the app asks for a flush", HostLog.recover(.flush), "host: asking the extension to flush"),
        Row(
            "a level skipped before the first heartbeat",
            HostLog.skipped(.rebuildPipeline),
            "host: no heartbeat since activation, skipping rebuildPipeline: no extension to receive it"
        ),
        Row("recovering names its level", HostLog.status(.recovering(.rebuildSurface)), "host: status recovering(rebuildSurface)"),
        Row("recovering by restarting the agent", HostLog.status(.recovering(.restartAgent)), "host: status recovering(restartAgent)"),
    ]

    @Test(arguments: rows)
    func `a recovery level is named as it is spelled`(row: Row<String, String>) {
        #expect(row.input == row.expected)
    }
}
