import FileKit
import Foundation

/// Secrets in the login Keychain, one generic password per account under Hangar's service. A test run keeps them
/// in memory, so it never reads or writes the real Keychain.
enum Keychain {
    static let service = "com.mathieuares.hangar"
    private static let store = Store.isOverridden ? FileKit.Keychain.inMemory(service: service) : FileKit.Keychain(service: service)

    static func read(_ account: String) -> String? {
        store.string(for: account)
    }

    /// Nil or an empty value forgets the secret.
    static func write(_ account: String, _ value: String?) {
        do { try store.set(value, for: account) } catch {
            Store.log.post(.error, "Can't keep the \(account) key in the Keychain: \(error.localizedDescription)", source: "Settings")
        }
    }
}
