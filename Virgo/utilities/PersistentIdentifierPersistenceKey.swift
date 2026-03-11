//
//  PersistentIdentifierPersistenceKey.swift
//  Virgo
//
//  Backward-compatible persistence key resolution for SwiftData identifiers.
//

import Foundation
import SwiftData
import CryptoKit

enum PersistentIdentifierPersistenceKey {
    struct Resolution<Value> {
        let canonicalKey: String
        let matchedKey: String
        let value: Value

        var needsMigration: Bool {
            canonicalKey != matchedKey
        }
    }

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

    static func resolve<Value>(
        for identifier: PersistentIdentifier,
        in persistedValues: [String: Value],
        logPrefix: String
    ) -> Resolution<Value>? {
        let canonicalKey = canonicalKey(for: identifier, logPrefix: logPrefix)
        if let value = persistedValues[canonicalKey] {
            return Resolution(canonicalKey: canonicalKey, matchedKey: canonicalKey, value: value)
        }

        let decoder = JSONDecoder()
        for (candidateKey, value) in persistedValues where candidateKey != canonicalKey {
            guard let candidateData = candidateKey.data(using: .utf8),
                  let decodedIdentifier = try? decoder.decode(PersistentIdentifier.self, from: candidateData),
                  decodedIdentifier == identifier else {
                continue
            }

            Logger.debug("\(logPrefix): Migrating legacy persistence key to canonical format")
            return Resolution(canonicalKey: canonicalKey, matchedKey: candidateKey, value: value)
        }

        return nil
    }
}
