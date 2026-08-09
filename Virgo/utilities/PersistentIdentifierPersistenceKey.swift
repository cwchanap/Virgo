//
//  PersistentIdentifierPersistenceKey.swift
//  Virgo
//
//  Current-format persistence key generation for SwiftData identifiers.
//

import Foundation
import SwiftData
import CryptoKit

enum PersistentIdentifierPersistenceKey {
    static func canonicalKey(for identifier: PersistentIdentifier, logPrefix: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(identifier)
            if let key = String(data: data, encoding: .utf8) {
                return key
            }
            Logger.error("\(logPrefix): Failed to convert PersistentIdentifier JSON data to UTF-8 string")
        } catch {
            Logger.error("\(logPrefix): Failed to JSON-encode PersistentIdentifier: \(error.localizedDescription)")
        }

        let stableIdentifier = String(describing: identifier)
        let inputData = Data(stableIdentifier.utf8)
        let digest = SHA256.hash(data: inputData)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        Logger.warning("\(logPrefix): Using SHA-256 fallback key for chart \(stableIdentifier.prefix(40))")
        return "chart_\(String(hashString.prefix(32)))"
    }
}
