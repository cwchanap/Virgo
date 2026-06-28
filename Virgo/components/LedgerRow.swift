import SwiftUI

/// A ruled ledger-line row container: content with a hairline rule beneath it.
struct LedgerRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.vertical, 14)
                .padding(.horizontal, Spacing.md)
            RuleDivider()
        }
    }
}
