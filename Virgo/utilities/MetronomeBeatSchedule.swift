//
//  MetronomeBeatSchedule.swift
//  Virgo
//

import Foundation

struct MetronomeBeatSchedule {
    let beatOriginTime: CFAbsoluteTime
    let beatInterval: TimeInterval
    let schedulingLeadTime: TimeInterval

    func audioTargetTime(forBeatNumber beatNumber: Int) -> CFAbsoluteTime {
        beatOriginTime + (Double(max(beatNumber, 1) - 1) * beatInterval)
    }

    func timerDeadline(forBeatNumber beatNumber: Int) -> CFAbsoluteTime {
        audioTargetTime(forBeatNumber: beatNumber) - max(0, schedulingLeadTime)
    }
}
