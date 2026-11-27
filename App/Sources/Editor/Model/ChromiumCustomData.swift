import Foundation

/// Chromium의 Web Custom Data 피클. 길이는 LE UInt32이며 문자열 패딩은 길이에 포함되지 않는다.
nonisolated enum ChromiumCustomData {
    static let notionBlocks = "text/_notion-blocks-v3-production"

    static func encode(_ entries: [String: String]) -> Data? {
        var payload = Data()
        func appendWord(_ value: Int, to data: inout Data) -> Bool {
            guard let word = UInt32(exactly: value) else { return false }
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
            return true
        }
        func appendString(_ string: String) -> Bool {
            guard appendWord(string.utf16.count, to: &payload) else { return false }
            for unit in string.utf16 {
                payload.append(UInt8(truncatingIfNeeded: unit))
                payload.append(UInt8(unit >> 8))
            }
            if !payload.count.isMultiple(of: 4) { payload.append(contentsOf: [0, 0]) }
            return true
        }
        guard appendWord(entries.count, to: &payload) else { return nil }
        for (key, value) in entries {
            guard appendString(key), appendString(value) else { return nil }
        }
        var data = Data()
        guard appendWord(payload.count, to: &data) else { return nil }
        data.append(payload)
        return data
    }

    static func decode(_ data: Data) -> [String: String]? {
        data.withUnsafeBytes { bytes in
            var offset = 0
            func word() -> Int? {
                guard bytes.count - offset >= 4 else { return nil }
                defer { offset += 4 }
                return Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
            }
            func string() -> String? {
                guard let count = word() else { return nil }
                let length = count * 2
                let aligned = length + (count.isMultiple(of: 2) ? 0 : 2)
                guard aligned <= bytes.count - offset else { return nil }
                defer { offset += aligned }
                let units = stride(from: offset, to: offset + length, by: 2).map { index in
                    UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: index, as: UInt16.self))
                }
                return String(validating: units, as: UTF16.self)
            }
            guard let size = word(), size == bytes.count - offset,
                  let count = word(), count <= (bytes.count - offset) / 8 else { return nil }
            var entries: [String: String] = [:]
            for _ in 0..<count {
                guard let key = string(), let value = string(), entries[key] == nil else { return nil }
                entries[key] = value
            }
            return offset == bytes.count ? entries : nil
        }
    }
}
