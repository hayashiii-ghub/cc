import AppKit
import CoreFoundation
import Foundation

private let bundleIdentifier = "work.hayashigoto.cc"
private let notificationPrefix = "work.hayashigoto.cc.demo."
private let supportedCommands = [
    "add-finder-selection",
    "clear-shelf",
    "show-shelf",
    "toggle-shelf",
    "use-menu-bar",
    "use-notch-island",
    "show-settings",
]

private func printUsage() {
    let commands = supportedCommands.joined(separator: "\n  ")
    FileHandle.standardError.write(
        Data("usage: cc-demo <command>\n\ncommands:\n  \(commands)\n".utf8)
    )
}

guard CommandLine.arguments.count == 2,
      supportedCommands.contains(CommandLine.arguments[1]) else {
    printUsage()
    exit(2)
}

guard !NSRunningApplication.runningApplications(
    withBundleIdentifier: bundleIdentifier
).isEmpty else {
    FileHandle.standardError.write(
        Data("cc: is not running. Start a debug build with `make run`.\n".utf8)
    )
    exit(1)
}

let command = CommandLine.arguments[1]
let notificationName = CFNotificationName(
    (notificationPrefix + command as NSString) as CFString
)
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    notificationName,
    nil,
    nil,
    true
)
print("Triggered cc: demo command: \(command)")
