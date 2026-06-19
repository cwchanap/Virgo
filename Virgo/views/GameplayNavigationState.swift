//
//  GameplayNavigationState.swift
//  Virgo
//

import Foundation

struct GameplayNavigationState {
    private(set) var selectedChart: Chart?

    var isShowingGameplay: Bool {
        selectedChart != nil
    }

    mutating func openGameplay(with chart: Chart) {
        selectedChart = chart
    }

    mutating func dismissGameplay() {
        selectedChart = nil
    }
}
