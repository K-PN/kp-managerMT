import Foundation
#if canImport(CryptoKit) && canImport(CommonCrypto)
import CryptoKit
import CommonCrypto
import Security

public actor LocalBackupService: BackupService {
    private let ledger: LedgerService
    private let limit = 256_000_000
    private struct Envelope: Codable {
        var version: Int = 1
        var encrypted: Bool
        var salt: Data?
        var rounds: Int?
        var digest: Data
        var payload: Data
    }
    public init(ledger: LedgerService) { self.ledger = ledger }
    public func export(password: String? = nil) async throws -> Data {
        let state = try await ledger.snapshot()
        try SnapshotValidator.validate(state)
        let plain = try JSONCoding.encode(state)
        guard plain.count <= limit else { throw LedgerError.invalid("Sao lưu vượt giới hạn 256 MB. Cần chia nhỏ kho ảnh trước khi xuất.") }
        let digest = Data(SHA256.hash(data: plain))
        let envelope: Envelope
        if let password, !password.isEmpty {
            guard password.count >= 10 else { throw LedgerError.invalid("Mật khẩu sao lưu cần ít nhất 10 ký tự.") }
            var salt = Data(count: 16)
            let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            guard status == errSecSuccess else { throw LedgerError.unavailable("Không tạo được khóa ngẫu nhiên.") }
            let key = try derive(password: password, salt: salt, rounds: 310_000)
            let sealed = try AES.GCM.seal(plain, using: key)
            guard let combined = sealed.combined else { throw LedgerError.corruptBackup }
            envelope = Envelope(encrypted: true, salt: salt, rounds: 310_000, digest: digest, payload: combined)
        } else { envelope = Envelope(encrypted: false, digest: digest, payload: plain) }
        return try JSONCoding.encode(envelope)
    }
    public func restore(_ data: Data, password: String? = nil, confirmed: Bool) async throws {
        guard confirmed else { throw LedgerError.invalid("Cần xác nhận khôi phục.") }
        guard data.count <= limit * 2 else { throw LedgerError.corruptBackup }
        let state: LedgerSnapshot
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1, envelope.payload.count <= limit + 64 else { throw LedgerError.corruptBackup }
            let plain: Data
            if envelope.encrypted {
                guard let salt = envelope.salt, salt.count == 16, envelope.rounds == 310_000,
                      let password, !password.isEmpty else { throw LedgerError.corruptBackup }
                let key = try derive(password: password, salt: salt, rounds: 310_000)
                plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.payload), using: key)
            } else { plain = envelope.payload }
            guard Data(SHA256.hash(data: plain)) == envelope.digest else { throw LedgerError.corruptBackup }
            state = try JSONDecoder().decode(LedgerSnapshot.self, from: plain)
        } catch { throw LedgerError.corruptBackup }
        try await ledger.restoreSnapshot(state, confirmed: true)
    }
    private func derive(password: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let passwordData = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: 32)
        let status = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), passwordData.count,
                                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, outputBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw LedgerError.corruptBackup }
        return SymmetricKey(data: output)
    }
}
#endif
