// usage: fakes <command words…>
// Posts a command to Livepaper's fakes run (App/Shell/FakesRemote.swift). The wired app does not listen.
// With LIVEPAPER_FAKES=<name> it reaches only the run started with `-fakesRemote <name>`.
import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !command.isEmpty else {
    FileHandle.standardError.write(Data("usage: fakes <command words…>\n".utf8))
    exit(2)
}
let run = ProcessInfo.processInfo.environment["LIVEPAPER_FAKES"].map { ".\($0)" } ?? ""
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.livepaper.fakes.command" + run), object: command, userInfo: nil, deliverImmediately: true
)
