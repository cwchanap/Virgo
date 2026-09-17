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
import Testing
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

    // The prior application-element value is captured verbatim inside and
    // the returned closure restores it — run in `defer` so the probe
    // cannot leak global accessibility state into the rest of the test
    // host, even on failure.
    let restoreEnhancedUI = setEnhancedUserInterface()
    defer { restoreEnhancedUI() }

    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    // The accessibility subtree materializes asynchronously: pump the run
    // loop in short increments and re-walk until a semantic label shows up
    // or the bounded deadline passes — never a fixed sleep. For an
    // unlabeled mount the full window doubles as the observation period
    // before judging absence.
    let deadline = Date().addingTimeInterval(2)
    var dump = walkAccessibilityTree(roots: [hostingView, window])
    while dump.labels.isEmpty, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        hostingView.layoutSubtreeIfNeeded()
        dump = walkAccessibilityTree(roots: [hostingView, window])
    }
    return dump
}

/// Sets `AXEnhancedUserInterface` on this process's application element —
/// SwiftUI materializes its accessibility subtree only for an enhanced-UI
/// client (what VoiceOver sets). Same-process call, no TCC needed.
/// Returns a closure restoring the prior value verbatim (neutral `false`
/// when none was set) so the probe leaks no global accessibility state.
///
/// Every AX status is classified: `.apiDisabled`/`.notImplemented` (the
/// xctest host cannot write the attribute — the informal-protocol walk
/// still sees SwiftUI's nodes there) and the read-side "unset" errors are
/// tolerated; anything unexpected is recorded as a test issue.
private func setEnhancedUserInterface() -> () -> Void {
    let application = AXUIElementCreateApplication(getpid())
    let attribute = "AXEnhancedUserInterface" as CFString
    var priorValue: CFTypeRef?
    switch AXUIElementCopyAttributeValue(application, attribute, &priorValue) {
    case .success:
        break
    case .noValue, .attributeUnsupported, .apiDisabled, .notImplemented:
        // No prior client state — the attribute reads as unset.
        priorValue = nil
    case let error:
        Issue.record("AXEnhancedUserInterface read failed: \(error.rawValue)")
        priorValue = nil
    }
    switch AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) {
    case .success, .apiDisabled, .notImplemented:
        break
    case let error:
        Issue.record("AXEnhancedUserInterface enable failed: \(error.rawValue)")
    }
    return {
        switch AXUIElementSetAttributeValue(
            application,
            attribute,
            priorValue ?? kCFBooleanFalse
        ) {
        case .success, .apiDisabled, .notImplemented:
            break
        case let error:
            Issue.record("AXEnhancedUserInterface restore failed: \(error.rawValue)")
        }
    }
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
