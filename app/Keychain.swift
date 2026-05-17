//
//  Keychain.swift
//  Compost — minimal Keychain wrapper.
//

import Foundation
import Security

enum KeychainKey: String {
    case notionToken         = "compost.notion.token"
    case parentPageId        = "compost.notion.parentPageId"
    case compostPileDbId     = "compost.notion.compostPileDbId"
    case frozenDraftsDbId    = "compost.notion.frozenDraftsDbId"
    case weeklyDigestsDbId   = "compost.notion.weeklyDigestsDbId"
    case cueCardsDbId        = "compost.notion.cueCardsDbId"
    case notionMemoryDbId    = "compost.notion.notionMemoryDbId"
    case memoryParentPageId  = "compost.notion.memoryParentPageId"
}

enum Keychain {
    static func get(_ key: KeychainKey) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func set(_ key: KeychainKey, _ value: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = value.data(using: .utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
