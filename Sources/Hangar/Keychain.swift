import Foundation
import Security

/// Secrets in the login Keychain, one generic password per account. A test run keeps them
/// in memory, so it never reads or writes the real Keychain.
enum Keychain {
    static let service = "com.mathieuares.hangar"
    private static var memory: [String: String] = [:]

    static func read(_ account: String) -> String? {
        if Store.isOverridden { return memory[account] }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String?) {
        if Store.isOverridden { memory[account] = value?.isEmpty == false ? value : nil; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
