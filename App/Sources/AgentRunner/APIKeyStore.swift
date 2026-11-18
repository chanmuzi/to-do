import Foundation
import Security

public protocol APIKeyStoring: Sendable {
    func key(for provider: APIProvider) throws -> Data?
    func setKey(_ value: Data?, for provider: APIProvider) throws
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    public init() {}

    private func query(_ provider: APIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "FloatingNotes.AgentRunner",
         kSecAttrAccount as String: provider.rawValue]
    }

    public func key(for provider: APIProvider) throws -> Data? {
        var request = query(provider)
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    public func setKey(_ value: Data?, for provider: APIProvider) throws {
        let selector = query(provider)
        guard let value else {
            let status = SecItemDelete(selector as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        let fields: [String: Any] = [kSecValueData as String: value,
                                      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemAdd(selector.merging(fields) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try check(SecItemUpdate(selector as CFDictionary, fields as CFDictionary))
        } else { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
