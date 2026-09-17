import Foundation

// The CLI forwards to the running app through its URL scheme, so the app stays
// the only process that writes the library. Commands arrive in M7 (docs/roadmap.md).
let usage = """
    usage: livepaper <command>

    No commands are available yet.
    """

FileHandle.standardError.write(Data((usage + "\n").utf8))
exit(EXIT_FAILURE)
