//
//  HostedAccessibilityProbe.swift
//  VirgoTests
//
//  HPA-166 Task 9 review fix — hosted macOS accessibility-tree traversal
//  for mounted-notation tests: window hosting, enhanced-UI enablement,
//  and informal-protocol label readback.
//

import SwiftUI
import Foundation
@testable import Virgo

#if os(macOS)
import AppKit
import ApplicationServices

/// Labels plus a diagnostic kind-per-node dump so an empty traversal says
/// *what* the tree exposed instead of a bare `[]`.
struct HostedAccessibilityDump {
    let labels: [String]
    let nodeKinds: [String]
}

/// Calls a no-arg accessibility selector returning a string, when the
/// object implements the informal protocol member.
private func performAXString(_ object: NSObject, _ selector: Selector) -> String? {
    guard object.responds(to: selector) else { return nil }
    return object.perform(selector)?.takeUnretainedValue() as? String
}

/// Calls a no-arg accessibility selector returning an array, when the
/// object implements the informal protocol member.
private func performAXList(_ object: NSObject, _ selector: Selector) -> [Any]? {
    guard object.responds(to: selector) else { return nil }
    return object.perform(selector)?.takeUnretainedValue() as? [Any]
}

/// Mounts the production sheet branch in a real `NSHostingView` inside an
/// offscreen window and walks its accessibility tree — collecting every
/// non-empty VoiceOver label. SwiftUI's `AccessibilityNode` conforms to
/// the informal `NSAccessibility` protocol, so `accessibilityLabel` /
/// `accessibilityChildren` are dispatched dynamically rather than through
/// a Swift-visible member.
@MainActor
func hostedAccessibilityLabels(
    of sheet: MountedSheet,
    viewport: CGSize
) -> HostedAccessibilityDump {
    let hostingView = NSHostingView(
        rootView: AnyView(
            GeometryReader { proxy in
                sheet.gameplayView.sheetMusicView(geometry: proxy)
            }
            .frame(width: viewport.width, height: viewport.height)
        )
    )
    hostingView.frame = CGRect(origin: .zero, size: viewport)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: viewport),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    // SwiftUI materializes its accessibility subtree only for an
    // "enhanced user interface" client — what VoiceOver sets on the
    // application element. Same-process call, no TCC needed.
    AXUIElementSetAttributeValue(
        AXUIElementCreateApplication(getpid()),
        "AXEnhancedUserInterface" as CFString,
        kCFBooleanTrue
    )
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    hostingView.layoutSubtreeIfNeeded()
    return walkAccessibilityTree(roots: [hostingView, window])
}

/// Breadth-first walk of the accessibility tree under `roots`.
private func walkAccessibilityTree(roots: [Any]) -> HostedAccessibilityDump {
    var labels: [String] = []
    var nodeKinds: [String] = []
    var queue = roots
    var visited = Set<ObjectIdentifier>()
    while let element = queue.popLast() {
        guard let object = element as? NSObject,
              visited.insert(ObjectIdentifier(object)).inserted else { continue }
        let label = performAXString(object, NSSelectorFromString("accessibilityLabel"))
        if let label, !label.isEmpty {
            labels.append(label)
        }
        var children = performAXList(object, NSSelectorFromString("accessibilityChildren")) ?? []
        children += performAXList(
            object, NSSelectorFromString("accessibilityChildrenInNavigationOrder")
        ) ?? []
        if let view = object as? NSView {
            children += view.subviews
        }
        nodeKinds.append("\(type(of: object))\(label.map { ":\($0)" } ?? "")")
        queue.append(contentsOf: children)
    }
    return HostedAccessibilityDump(labels: labels, nodeKinds: nodeKinds)
}
#endif
