import Darwin
import Foundation

/// 표시용 클레임만 읽는다. 서명을 검증한 로그인 판정은 CLI에 맡긴다.
struct CodexIdentity {
    let email: String?
    let plan: String?

    static func read(in directory: URL) -> Self? {
        let descriptor = open(directory.appending(path: "auth.json").path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let limit = 1_048_576
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= limit, let data = try? file.read(upToCount: limit + 1), data.count <= limit,
              let auth = try? JSONDecoder().decode(Auth.self, from: data) else { return nil }
        let parts = auth.tokens.id_token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let json = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let account = claims["https://api.openai.com/auth"] as? [String: Any]
        return Self(email: claims["email"] as? String, plan: account?["chatgpt_plan_type"] as? String)
    }

    private struct Auth: Decodable {
        struct Tokens: Decodable { let id_token: String }
        let tokens: Tokens
    }
}
