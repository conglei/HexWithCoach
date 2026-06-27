//
//  CoachKeychain.swift
//  HexEngine (shared: macOS Hex + iOS HexIOS)
//
//  Plain Keychain helper for the BYOK provider key. Foundation + Security only
//  (no TCA), so it works the same on macOS and iOS. The key is stored per-device
//  and never synced — `kSecAttrAccessibleAfterFirstUnlock`, no iCloud Keychain —
//  so a user's API key doesn't leave the device through our sync.
//

import Foundation
import HexCore
import os
import Security

enum CoachKeychain {
    /// Keychain service namespace for Coach secrets.
    static let service = "stonefrontier.hex.coach"

    /// Account key for the Gemini BYOK API key.
    static let geminiAPIKeyAccount = "gemini.apiKey"

    private static let log = HexLog.coach

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            if status != errSecItemNotFound {
                log.error("Keychain read failed for \(account, privacy: .public): OSStatus \(status)")
            }
            return nil
        }
        return value
    }

    @discardableResult
    static func write(_ account: String, _ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound {
            log.error("Keychain update failed for \(account, privacy: .public): OSStatus \(updateStatus)")
            return false
        }

        var addQuery = query
        for (key, value) in attributes { addQuery[key] = value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("Keychain add failed for \(account, privacy: .public): OSStatus \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
