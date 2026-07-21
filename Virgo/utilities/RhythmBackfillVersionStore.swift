//
//  RhythmBackfillVersionStore.swift
//  Virgo
//

import Foundation

protocol RhythmBackfillVersionStoring {
    func completedVersion() -> Int
    func markCompleted(version: Int)
}

struct RhythmBackfillVersionStore: RhythmBackfillVersionStoring {
    static let currentVersion = 1

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "Virgo.RhythmBackfill.completedVersion"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func completedVersion() -> Int {
        userDefaults.integer(forKey: key)
    }

    func markCompleted(version: Int) {
        userDefaults.set(version, forKey: key)
    }
}
