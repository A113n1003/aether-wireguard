import Foundation
import Security
import Darwin

public struct ProfileMetadata: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.createdAt = createdAt
    }
}

public enum ProfileRepositoryError: Error, LocalizedError {
    case storage(String)
    case keychain(OSStatus)
    case missing

    public var errorDescription: String? {
        switch self {
        case .storage(let message): return message
        case .missing: return "找不到此配置。请重新导入，或检查钥匙串是否已解锁。"
        case .keychain(let status):
            switch status {
            case errSecAuthFailed, errSecInteractionNotAllowed: return "无法访问钥匙串。请解锁登录钥匙串后重试。"
            case errSecUserCanceled: return "已取消钥匙串授权，配置未保存。"
            default: return "钥匙串操作失败（\(status)）。请检查钥匙串权限后重试。"
            }
        }
    }
}

/// 在调用方的同一个 actor 上使用。磁盘仅保存元信息，完整配置保存在系统钥匙串。
public final class ProfileRepository {
    private let directory: URL
    private let service = "io.aether.wireguard"
    private var metadataURL: URL { directory.appendingPathComponent("profiles.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aether", isDirectory: true)
    }

    public func list() throws -> [ProfileMetadata] {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([ProfileMetadata].self, from: Data(contentsOf: metadataURL))
            guard Set(decoded.map(\.id)).count == decoded.count else {
                throw ProfileRepositoryError.storage("配置索引包含重复 ID，请恢复备份后重试。")
            }
            return decoded.sorted { $0.createdAt < $1.createdAt }
        } catch let error as ProfileRepositoryError { throw error }
        catch { throw ProfileRepositoryError.storage("配置索引无法读取；原文件已保留。请检查文件权限或恢复备份。") }
    }

    public func configuration(for id: UUID) throws -> WGConfiguration {
        guard let data = try readSecret(id: id), let text = String(data: data, encoding: .utf8) else {
            throw ProfileRepositoryError.missing
        }
        return try WGConfiguration(text: text)
    }

    public func save(metadata: ProfileMetadata, configuration: WGConfiguration) throws {
        let name = metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProfileRepositoryError.storage("配置名称应为 1–100 个字符，且不能包含控制字符。")
        }
        var profiles = try list()
        let record = ProfileMetadata(id: metadata.id, name: name, createdAt: metadata.createdAt)
        if let index = profiles.firstIndex(where: { $0.id == record.id }) { profiles[index] = record }
        else { profiles.append(record) }
        let oldSecret = try readSecret(id: metadata.id)
        // 只有钥匙串写入成功，才发布新的元信息。
        try writeSecret(Data(configuration.canonicalText.utf8), id: metadata.id)
        do { try writeMetadata(profiles) }
        catch {
            do {
                if let oldSecret { try writeSecret(oldSecret, id: metadata.id) }
                else { try removeSecret(id: metadata.id) }
            } catch {
                throw ProfileRepositoryError.storage("配置索引写入失败，钥匙串回滚也未完成。请检查存储权限后重新保存。")
            }
            throw error
        }
    }

    public func delete(id: UUID) throws {
        let oldProfiles = try list()
        guard oldProfiles.contains(where: { $0.id == id }) else { return }
        let secret = try readSecret(id: id)
        try removeSecret(id: id)
        do { try writeMetadata(oldProfiles.filter { $0.id != id }) }
        catch {
            if let secret {
                do { try writeSecret(secret, id: id) }
                catch { throw ProfileRepositoryError.storage("配置索引更新失败，钥匙串回滚也未完成。请检查存储权限后重试。") }
            }
            throw error
        }
    }

    private func query(id: UUID) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
         kSecAttrAccount: id.uuidString, kSecAttrSynchronizable: false]
    }
    private func readSecret(id: UUID) throws -> Data? {
        var request = query(id: id)
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ProfileRepositoryError.keychain(status) }
        guard let data = result as? Data else { throw ProfileRepositoryError.storage("钥匙串中的配置格式无效。") }
        return data
    }
    private func writeSecret(_ data: Data, id: UUID) throws {
        let request = query(id: id)
        let attributes: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = request
            insertion[kSecValueData] = data
            insertion[kSecAttrLabel] = "Aether WireGuard configuration"
            insertion[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ProfileRepositoryError.keychain(status) }
    }
    private func removeSecret(id: UUID) throws {
        let status = SecItemDelete(query(id: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProfileRepositoryError.keychain(status) }
    }
    private func writeMetadata(_ profiles: [ProfileMetadata]) throws {
        let temporary = directory.appendingPathComponent(".profiles-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw ProfileRepositoryError.storage("无法创建配置索引。")
            }
            // 同目录 rename 原子替换，并保留临时文件的 0600 权限。
            let result = temporary.path.withCString { source in
                metadataURL.path.withCString { destination in Darwin.rename(source, destination) }
            }
            guard result == 0 else { throw ProfileRepositoryError.storage("无法更新配置索引。") }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw ProfileRepositoryError.storage("配置索引写入失败。请检查可用磁盘空间和目录权限。")
        }
    }
}
