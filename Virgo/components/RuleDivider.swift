import SwiftUI

struct RuleDivider: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Rectangle().fill(theme.rule).frame(height: RuleWeight.hairline)
    }
}
