import AppKit

let options: LaunchOptions
do {
    options = try LaunchOptions(arguments: CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(64)
}

let application = NSApplication.shared
let delegate = AppDelegate(options: options)
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
