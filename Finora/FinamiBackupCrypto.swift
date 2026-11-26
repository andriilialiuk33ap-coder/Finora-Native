import Foundation
import CryptoKit
import CommonCrypto
import Security

// Versioned portable encrypted envelope; password-derived key, random salt and AES-GCM.
private struct FinamiEncryptedEnvelope: Codable {
    var version: Int = 1
    var salt: Data
    var sealed: Data
}
private enum FinamiCryptoError: LocalizedError {
    case invalid, password, random
    var errorDescription: String? { switch self { case .invalid: return "Непідтримуваний або пошкоджений файл."; case .password: return "Неправильний пароль або пошкоджена копія."; case .random: return "Не вдалося створити ключ." } }
}
enum FinamiBackupCrypto {
    static func key(_ password: String, salt: Data) throws -> SymmetricKey {
        let bytes = Array(password.utf8); let saltBytes = Array(salt); var output = [UInt8](repeating: 0, count: 32)
        guard !bytes.isEmpty, bytes.count <= 1024, saltBytes.count == 16 else { throw FinamiCryptoError.invalid }
        let status = bytes.withUnsafeBytes { p in saltBytes.withUnsafeBytes { s in output.withUnsafeMutableBytes { o in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.bindMemory(to: Int8.self).baseAddress, bytes.count, s.bindMemory(to: UInt8.self).baseAddress, saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, o.bindMemory(to: UInt8.self).baseAddress, 32)
        } } }
        guard status == kCCSuccess else { throw FinamiCryptoError.invalid }; return SymmetricKey(data: output)
    }
    static func seal(_ data: Data, password: String) throws -> Data {
        var salt = [UInt8](repeating: 0, count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw FinamiCryptoError.random }
        let saltData = Data(salt)
        let box = try AES.GCM.seal(data, using: key(password, salt: saltData))
        guard let combined = box.combined else { throw FinamiCryptoError.invalid }
        let encoded = try JSONEncoder().encode(FinamiEncryptedEnvelope(salt: saltData, sealed: combined))
        guard encoded.count <= 150_000_000 else { throw FinamiCryptoError.invalid }
        return encoded
    }
    static func open(_ data: Data, password: String) throws -> Data {
        guard data.count <= 150_000_000 else { throw FinamiCryptoError.invalid }
        let e = try JSONDecoder().decode(FinamiEncryptedEnvelope.self, from: data)
        guard e.version == 1, e.salt.count == 16 else { throw FinamiCryptoError.invalid }
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: e.sealed), using: key(password, salt: e.salt)) } catch { throw FinamiCryptoError.password }
    }
}
