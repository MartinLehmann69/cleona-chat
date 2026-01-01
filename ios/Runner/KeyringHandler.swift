import Flutter
import Security
import Foundation

/// §3.7 OS Keyring: iOS Keychain Services (kSecClassGenericPassword).
///
/// Stores binary data as base64-encoded strings in the default Keychain.
/// Keys are scoped by service="cleona" and account=name. Data protection
/// class: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — available
/// after first unlock, not migrated to new devices (forces re-derive from
/// seed phrase on device change, which is the intended recovery flow).
class KeyringHandler: NSObject, FlutterPlugin {
    static let channelName = "chat.cleona/keyring"
    private static let service = "cleona"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = KeyringHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "store":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String,
                  let data = args["data"] as? String else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "name and data required", details: nil))
                return
            }
            let ok = keychainStore(name: name, value: data)
            result(ok)

        case "load":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "name required", details: nil))
                return
            }
            result(keychainLoad(name: name))

        case "delete":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "name required", details: nil))
                return
            }
            let ok = keychainDelete(name: name)
            result(ok)

        case "loadAll":
            result(keychainLoadAll())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Keychain Operations

    private func keychainStore(name: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first (SecItemAdd fails on duplicate).
        keychainDelete(name: name)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeyringHandler.service,
            kSecAttrAccount as String: name,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[Keyring] SecItemAdd failed for \"\(name)\": \(status)")
        }
        return status == errSecSuccess
    }

    private func keychainLoad(name: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeyringHandler.service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    @discardableResult
    private func keychainDelete(name: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeyringHandler.service,
            kSecAttrAccount as String: name,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func keychainLoadAll() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeyringHandler.service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess,
              let entries = items as? [[String: Any]] else {
            return [:]
        }
        var result: [String: String] = [:]
        for entry in entries {
            guard let account = entry[kSecAttrAccount as String] as? String,
                  let data = entry[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                continue
            }
            result[account] = value
        }
        return result
    }
}
