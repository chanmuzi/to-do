import Foundation
import Models

package struct ProposalInbox: Sendable {
    let root: URL
    package init(location: StoreLocation) {
        root = location.stateDirectory.appending(path: "agent/intake", directoryHint: .isDirectory)
    }
    package func folder(_ run: UUID) -> URL { root.appending(path: run.uuidString, directoryHint: .isDirectory) }

    package func prepare(_ run: UUID) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = folder(run)
        try manager.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    package func remove(_ run: UUID) throws {
        do { try FileManager.default.removeItem(at: folder(run)) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }

    package func proposals(for request: AgentRequest, source: NoteID?) throws -> [AgentProposal] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: folder(request.runID), includingPropertiesForKeys: Array(keys),
                                                                options: .skipsHiddenFiles)
        let entries = try files.map { ($0, try $0.resourceValues(forKeys: keys)) }
        return try entries.sorted {
            ($0.1.creationDate ?? .distantPast, $0.0.lastPathComponent) < ($1.1.creationDate ?? .distantPast, $1.0.lastPathComponent)
        }.map { url, info in
            guard url.pathExtension == "json", info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize, size <= 256 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let input = try JSONDecoder().decode(TodoSubmission.self, from: Data(contentsOf: url))
            guard !input.noteID.isEmpty, !input.noteID.hasPrefix("."), !input.noteID.contains("/"), !input.noteID.utf8.contains(0),
                  TodoSubmission.valid(lines: input.lines) else { throw CocoaError(.fileReadCorruptFile) }
            return .submitted(input, key: url.deletingPathExtension().lastPathComponent, request: request, source: source)
        }
    }
}
