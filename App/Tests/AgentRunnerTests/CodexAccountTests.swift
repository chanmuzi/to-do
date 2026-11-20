import Foundation
import Store
import Testing
@testable import AgentRunner

@Suite struct CodexAccountTests {
    @Test func isolatedClaimsAreOptionalAndReadOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let connection = try AgentConnection(provider: .codex, location: .isolated(notesDirectory: root))
        defer { try! FileManager.default.removeItem(at: root) }
        let cli = root.appending(path: "codex")
        try "#!/bin/sh\necho 'Logged in using ChatGPT' >&2".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let installation = AgentInstallation(provider: .codex, executable: cli, version: "fake", node: nil)
        let auth = connection.config.appending(path: "auth.json")
        let claims = Data(#"{"email":"me@example.com","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#.utf8)
        let payload = claims.base64EncodedString().replacingOccurrences(of: "=", with: "")
        let valid = try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": "fake.\(payload).fake"]])
        for contents in [nil, Data("{}".utf8), Data(#"{"tokens":{"id_token":"bad"}}"#.utf8), valid] {
            if let contents { try contents.write(to: auth) }
            let account = try await connection.account(installation)
            #expect(account.loggedIn && account.method == "ChatGPT")
            #expect(account.email == (contents == valid ? "me@example.com" : nil))
            #expect(account.subscription == (contents == valid ? "plus" : nil))
            if let contents { #expect(try Data(contentsOf: auth) == contents) }
        }
    }
}
