import Foundation
import IOKit
import CSmc

/// AppleSMC 를 읽는 가장 단순한 경로. `IOConnectCallStructMethod`(index 2) 하나만 씁니다.
/// 읽기 전용이라 root 권한이 필요 없습니다.
struct SMCError: Error, CustomStringConvertible {
    let text: String
    var description: String { text }
}

final class SMC {
    private var conn: io_connect_t = 0
    private var infoCache: [UInt32: PWKeyInfo] = [:]

    init() throws {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == KERN_SUCCESS else {
            throw SMCError(text: "AppleSMC 서비스 조회 실패")
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS else { continue }
            guard String(cString: nameBuffer) == "AppleSMCKeysEndpoint" else { continue }

            let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
            guard kr == KERN_SUCCESS, conn != 0 else {
                throw SMCError(text: "IOServiceOpen 실패(\(kr))")
            }
        }

        guard conn != 0 else { throw SMCError(text: "AppleSMCKeysEndpoint 를 찾지 못함") }
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    /// 4바이트 float("flt ") 키를 와트 같은 실수로 읽는다. 없거나 타입이 다르면 nil.
    func float(_ key: String) -> Double? {
        guard let id = Self.keyID(key), let info = keyInfo(id) else { return nil }
        guard info.dataSize == 4, info.dataType == Self.keyID("flt ") else { return nil }

        var request = pwRequestReadBytes(id, info)
        var response = PWKeyData()
        guard transact(&request, &response) else { return nil }
        return Double(pwFloatValue(&response))
    }

    private func keyInfo(_ id: UInt32) -> PWKeyInfo? {
        if let cached = infoCache[id] { return cached }
        var request = pwRequestReadKeyInfo(id)
        var response = PWKeyData()
        guard transact(&request, &response) else { return nil }
        infoCache[id] = response.keyInfo
        return response.keyInfo
    }

    private func transact(_ input: inout PWKeyData, _ output: inout PWKeyData) -> Bool {
        var outSize = MemoryLayout<PWKeyData>.size
        let kr = IOConnectCallStructMethod(
            conn, 2,
            &input, MemoryLayout<PWKeyData>.size,
            &output, &outSize
        )
        guard kr == KERN_SUCCESS else { return false }
        return output.result == 0        // 132 는 "키 없음"
    }

    private static func keyID(_ name: String) -> UInt32? {
        let bytes = Array(name.utf8)
        guard bytes.count == 4 else { return nil }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }
}

// MARK: - 키 열거 & 범용 디코딩 (온도 키 탐색용)

extension SMC {
    /// SMC가 노출하는 키 개수 (#KEY)
    var keyCount: Int? { rawValue("#KEY").flatMap { Int(Self.u32BE($0.bytes)) } }

    /// 인덱스로 키 이름
    func keyName(at index: Int) -> String? {
        var request = pwRequestReadKeyByIndex(UInt32(index))
        var response = PWKeyData()
        guard transact(&request, &response) else { return nil }
        return name(of: response.key)
    }

    /// 접두어로 시작하는 키 이름만 열거한다 (온도 키처럼 이름 규칙이 정해진 경우).
    func keys(prefixedBy prefix: String) -> [String] {
        guard let count = keyCount else { return [] }
        var result: [String] = []
        result.reserveCapacity(64)
        for index in 0..<count {
            guard let name = keyName(at: index), name.hasPrefix(prefix) else { continue }
            result.append(name)
        }
        return result
    }

    struct Reading {
        var key: String
        var type: String     // FourCC: "sp78", "flt ", "fpe2" …
        var bytes: [UInt8]
        var value: Double?   // 타입을 해석했을 때의 실수값
    }

    /// 키 이름으로 원시 값 + 타입을 읽고, 알려진 수치 타입은 실수로 해석한다.
    func reading(_ key: String) -> Reading? {
        guard let id = Self.keyID(key), let info = keyInfo(id) else { return nil }
        var request = pwRequestReadBytes(id, info)
        var response = PWKeyData()
        guard transact(&request, &response) else { return nil }

        let size = Int(info.dataSize)
        let type = name(of: info.dataType)
        let bytes = Array(withUnsafeBytes(of: response.bytes) { Array($0) }.prefix(size))
        return Reading(key: key, type: type, bytes: bytes, value: decode(type: type, bytes: bytes))
    }

    private func rawValue(_ key: String) -> Reading? { reading(key) }

    private static func u32BE(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else { return 0 }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    private func name(of packed: UInt32) -> String {
        String(bytes: withUnsafeBytes(of: packed.bigEndian, Array.init), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    /// Apple Silicon 센서에서 실제로 보는 타입만 해석한다.
    /// (타입 FourCC는 이름으로 뽑을 때 공백이 trim 되므로 공백 없이 비교한다.)
    private func decode(type rawType: String, bytes: [UInt8]) -> Double? {
        switch rawType.trimmingCharacters(in: .whitespaces) {
        case "flt" where bytes.count >= 4:
            return Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
        case "sp78" where bytes.count >= 2:      // 부호 있는 8.8 고정소수점 (big-endian)
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "fpe2" where bytes.count >= 2:      // 부호 없는 14.2
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "iio" where bytes.count >= 4:
            return Double(Int32(bitPattern: Self.u32BE(bytes)))
        default:
            return nil
        }
    }
}
