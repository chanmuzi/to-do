import Foundation

let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let trash = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let files = FileManager.default
let timestamp = DateFormatter()
timestamp.dateFormat = "yyyyMMdd-HHmmss"
timestamp.locale = Locale(identifier: "en_US_POSIX")

do {
    try files.createDirectory(at: trash, withIntermediateDirectories: true)
    var destination = trash.appendingPathComponent(source.lastPathComponent)
    let datedName = source.deletingPathExtension().lastPathComponent + "-" + timestamp.string(from: Date())
    var collision = 0
    while true {
        do {
            try files.moveItem(at: source, to: destination)
            print("이전 앱을 휴지통으로 옮겼습니다: \(destination.path)")
            break
        } catch CocoaError.fileWriteFileExists {
            collision += 1
            let suffix = collision == 1 ? "" : "-\(collision)"
            destination = trash.appendingPathComponent(datedName + suffix + ".app")
        }
    }
} catch {
    FileHandle.standardError.write(Data("이전 앱을 휴지통으로 옮기지 못했습니다: \(error.localizedDescription)\n".utf8))
    exit(1)
}
