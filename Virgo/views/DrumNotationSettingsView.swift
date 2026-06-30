//
//  DrumNotationSettingsView.swift
//  Virgo
//
//  Created by Claude Code on 14/8/2025.
//
// swiftlint:disable file_length type_body_length cyclomatic_complexity function_body_length

import SwiftUI

struct DrumNotationSettingsView: View {
    @StateObject private var settingsManager = DrumNotationSettingsManager()
    @State private var showResetAlert = false
    @State private var draggedDrumType: DrumType?
    @State private var dragOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    
    private let staffHeight: CGFloat = 200
    private let staffLineSpacing: CGFloat = 20
    private let noteSize: CGFloat = 32
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                #if os(macOS)
                // Title section with back button for macOS
                LedgerRow {
                    HStack {
                        Button(action: { dismiss() }, label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(theme.primary)
                                Text("Back")
                                    .font(.headline)
                                    .foregroundColor(theme.primary)
                            }
                        })
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        Text("Drum Notation")
                            .font(AppType.display)
                            .foregroundColor(theme.primary)

                        Spacer()
                    }
                }
                #endif

                // Header Section
                headerSection

                // Interactive Staff Section
                interactiveStaffSection

                // Instructions
                instructionsSection

                // Reset Section
                resetSection
            }
            .padding(.top, 20)
        }
        .appSurface()
        #if os(iOS)
        .navigationTitle("Drum Notation")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            settingsManager.loadSettings()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        LedgerRow {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(theme.accent)
                    Text("Drum Note Positions")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }

                Text("Drag the drum symbols to position them on the staff lines. " +
                     "This controls where each drum appears in the musical notation.")
                    .font(.hanken(12))
                    .foregroundColor(theme.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
    
    // MARK: - Interactive Staff Section
    
    private var interactiveStaffSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow {
                HStack {
                    Image(systemName: "hand.draw")
                        .foregroundColor(theme.accent)
                    Text("Interactive Staff")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }
            }

            // Staff with draggable notes
            ZStack {
                // Staff lines and notes
                GeometryReader { geometry in
                    let staffWidth = geometry.size.width
                    let staffCenterY = (staffHeight + 100) / 2

                    ZStack {
                        // Staff lines (5 lines)
                        VStack(spacing: staffLineSpacing) {
                            ForEach(0..<5) { _ in
                                Rectangle()
                                    .fill(theme.primary.opacity(0.5))
                                    .frame(height: 2)
                            }
                        }
                        .frame(height: 4 * staffLineSpacing)
                        .position(x: staffWidth / 2, y: staffCenterY)

                        // Virtual guide lines - extend the main VStack pattern seamlessly
                        VStack(spacing: staffLineSpacing) {
                            // Above-staff virtual lines (4 additional lines above)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)

                            // Main staff lines (transparent - handled by the main VStack)
                            ForEach(0..<5) { _ in
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 2)
                            }

                            // Below-staff virtual lines (4 additional lines below)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                            Rectangle()
                                .fill(theme.rule)
                                .frame(height: 2)
                        }
                        .frame(height: 12 * staffLineSpacing) // Total: 4 above + 4 main + 4 below = 12 gaps
                        .position(x: staffWidth / 2, y: staffCenterY)

                        // Draggable drum notes
                        ForEach(DrumType.allCases, id: \.self) { drumType in
                            draggableDrumNote(
                                drumType: drumType,
                                staffWidth: staffWidth,
                                staffCenterY: staffCenterY
                            )
                        }
                    }
                }
                .frame(height: staffHeight + 200)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            RuleDivider()
        }
    }
    
    // MARK: - Instructions Section
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(theme.accent)
                    Text("How to Use")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }
            }
            instructionRow(icon: "hand.point.up.left", text: "Drag drum symbols up or down to position them")
            instructionRow(icon: "line.3.horizontal", text: "Place symbols on staff lines or between them")
            instructionRow(icon: "music.note", text: "Changes apply to all gameplay views")
            instructionRow(icon: "arrow.clockwise", text: "Use Reset to restore default positions")
        }
    }

    private func instructionRow(icon: String, text: String) -> some View {
        LedgerRow {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(theme.secondary)
                    .frame(width: 16)
                Text(text)
                    .font(.hanken(12))
                    .foregroundColor(theme.secondary)
                Spacer()
            }
        }
    }
    
    // MARK: - Draggable Drum Note
    
    private func draggableDrumNote(drumType: DrumType, staffWidth: CGFloat, staffCenterY: CGFloat) -> some View {
        let currentPosition = settingsManager.getNotePosition(for: drumType)
        let yPosition = staffCenterY + yOffsetForPosition(currentPosition)
        let xPosition = xPositionForDrumType(drumType, staffWidth: staffWidth)
        
        return VStack(spacing: 4) {
            // Drum symbol
            Text(drumType.symbol)
                .font(.system(size: noteSize))
                .foregroundColor(draggedDrumType == drumType ? theme.accent : theme.primary)
                .background(
                    Circle()
                        .fill(draggedDrumType == drumType ? theme.accent.opacity(0.2) : Color.clear)
                        .frame(width: noteSize + 8, height: noteSize + 8)
                )

            // Drum name
            Text(drumType.displayName)
                .font(.system(size: 10))
                .foregroundColor(theme.secondary)
                .multilineTextAlignment(.center)
        }
        .position(x: xPosition, y: yPosition)
        .offset(draggedDrumType == drumType ? dragOffset : .zero)
        .scaleEffect(draggedDrumType == drumType ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: draggedDrumType == drumType)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if draggedDrumType == nil {
                        draggedDrumType = drumType
                    }
                    if draggedDrumType == drumType {
                        // Calculate the target Y position based on drag
                        let targetY = yPosition + value.translation.height
                        let relativeY = targetY - staffCenterY
                        
                        // Create extended snapping positions including additional guide lines
                        let extendedPositions: [CGFloat] = [
                            -6.0, -5.0, -4.5, -4.0, -3.5, -3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0,
                            0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0
                        ]
                        
                        let normalizedTarget = relativeY / staffLineSpacing
                        let nearestNormalized = extendedPositions.min {
                            abs($0 - normalizedTarget) < abs($1 - normalizedTarget)
                        } ?? 0.0
                        let nearestY = nearestNormalized * staffLineSpacing
                        
                        // Snap to the nearest position
                        dragOffset = CGSize(width: 0, height: nearestY - (yPosition - staffCenterY))
                    }
                }
                .onEnded { value in
                    if draggedDrumType == drumType {
                        let targetY = yPosition + value.translation.height
                        let relativeY = targetY - staffCenterY
                        let newPosition = positionForYOffset(relativeY)
                        settingsManager.setNotePosition(newPosition, for: drumType)
                        
                        draggedDrumType = nil
                        dragOffset = .zero
                    }
                }
        )
    }
    
    // MARK: - Position Calculation Helpers
    
    private func yOffsetForPosition(_ position: GameplayLayout.NotePosition) -> CGFloat {
        switch position {
        // Extended positions above staff
        case .aboveLine9: return -9 * staffLineSpacing
        case .aboveLine8: return -8 * staffLineSpacing
        case .aboveLine7: return -7 * staffLineSpacing
        case .aboveLine6: return -6 * staffLineSpacing
        case .aboveLine5: return -5 * staffLineSpacing
        
        // Main staff positions
        case .line5: return -4 * staffLineSpacing
        case .spaceBetween4And5: return -3.5 * staffLineSpacing
        case .line4: return -3 * staffLineSpacing
        case .spaceBetween3And4: return -2.5 * staffLineSpacing
        case .line3: return -2 * staffLineSpacing
        case .spaceBetween2And3: return -1.5 * staffLineSpacing
        case .line2: return -1 * staffLineSpacing
        case .spaceBetween1And2: return -0.5 * staffLineSpacing
        case .line1: return 0 * staffLineSpacing
        
        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return 0.5 * staffLineSpacing
        case .belowLine1: return 1 * staffLineSpacing
        case .belowLine2: return 2 * staffLineSpacing
        case .belowLine3: return 3 * staffLineSpacing
        case .belowLine4: return 4 * staffLineSpacing
        case .belowLine5: return 5 * staffLineSpacing
        case .belowLine6: return 6 * staffLineSpacing
        }
    }
    
    // Extended positions for better above and below staff support
    private func extendedYOffsetForNormalizedValue(_ normalizedOffset: CGFloat) -> CGFloat {
        // Add more granular positions above and below staff
        let clampedOffset = max(-6.5, min(5.5, normalizedOffset)) // Extend range symmetrically
        return clampedOffset * staffLineSpacing
    }
    
    private func positionForYOffset(_ yOffset: CGFloat) -> GameplayLayout.NotePosition {
        let normalizedOffset = yOffset / staffLineSpacing
        
        // Find the closest position with full extended range
        let positions: [(GameplayLayout.NotePosition, CGFloat)] = [
            // Extended positions above staff
            (.aboveLine9, -9.0),
            (.aboveLine8, -8.0),
            (.aboveLine7, -7.0),
            (.aboveLine6, -6.0),
            (.aboveLine5, -5.0),
            
            // Main staff positions
            (.line5, -4.0),
            (.spaceBetween4And5, -3.5),
            (.line4, -3.0),
            (.spaceBetween3And4, -2.5),
            (.line3, -2.0),
            (.spaceBetween2And3, -1.5),
            (.line2, -1.0),
            (.spaceBetween1And2, -0.5),
            (.line1, 0.0),
            
            // Extended positions below staff
            (.spaceBetweenLine1AndBelow, 0.5),
            (.belowLine1, 1.0),
            (.belowLine2, 2.0),
            (.belowLine3, 3.0),
            (.belowLine4, 4.0),
            (.belowLine5, 5.0),
            (.belowLine6, 6.0)
        ]
        
        // Allow full extended range
        let clampedOffset = max(-9.5, min(6.5, normalizedOffset))
        
        let closestPosition = positions.min { abs($0.1 - clampedOffset) < abs($1.1 - clampedOffset) }
        return closestPosition?.0 ?? .line3
    }
    
    private func xPositionForDrumType(_ drumType: DrumType, staffWidth: CGFloat) -> CGFloat {
        let drumTypes = DrumType.allCases.sorted(by: { $0.sortOrder < $1.sortOrder })
        let index = drumTypes.firstIndex(of: drumType) ?? 0
        let spacing = staffWidth / CGFloat(drumTypes.count + 1)
        return spacing * CGFloat(index + 1)
    }
    
    // MARK: - Reset Section
    
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerRow {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(theme.accent)
                    Text("Reset Settings")
                        .font(AppType.headline)
                        .foregroundColor(theme.primary)
                    Spacer()
                }
            }

            LedgerRow {
                Button {
                    showResetAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(theme.accent)
                        Text("Reset All Positions to Default")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(theme.accent)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.accent.opacity(0.4), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .alert("Reset Drum Notation", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        settingsManager.resetToDefaults()
                    }
                } message: {
                    Text("This will reset all drum note positions to their default staff line assignments. " +
                         "This action cannot be undone.")
                }
            }
        }
    }
}

// MARK: - Settings Manager

class DrumNotationSettingsManager: ObservableObject {
    @Published private var notePositions: [DrumType: GameplayLayout.NotePosition] = [:]

    private let userDefaults: UserDefaults
    static let settingsKey = "DrumNotationSettings"
    private var settingsKey: String { Self.settingsKey }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.notePositions = Self.loadPositions(from: userDefaults)
    }

    /// Pure loader usable from non-UI contexts (e.g. gameplay view model).
    /// Returns every drum type, falling back to its default note position when no override is persisted.
    static func loadPositions(
        from userDefaults: UserDefaults = .standard
    ) -> [DrumType: GameplayLayout.NotePosition] {
        var positions: [DrumType: GameplayLayout.NotePosition] = [:]

        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            for (keyString, positionString) in decoded {
                let drumType = DrumType(storageKey: keyString)
                    ?? DrumType.allCases.first(where: { $0.description == keyString })
                if let drumType,
                   let position = GameplayLayout.NotePosition.allCases.first(where: { $0.rawValue == positionString }) {
                    positions[drumType] = position
                }
            }
        }

        for drumType in DrumType.allCases where positions[drumType] == nil {
            positions[drumType] = drumType.notePosition
        }

        return positions
    }

    func loadSettings() {
        notePositions = Self.loadPositions(from: userDefaults)
    }
    
    func saveSettings() {
        let encoded = notePositions.reduce(into: [String: String]()) { result, pair in
            result[pair.key.storageKey] = pair.value.rawValue
        }
        
        if let data = try? JSONEncoder().encode(encoded) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }
    
    func getNotePosition(for drumType: DrumType) -> GameplayLayout.NotePosition {
        return notePositions[drumType] ?? drumType.notePosition
    }
    
    func setNotePosition(_ position: GameplayLayout.NotePosition, for drumType: DrumType) {
        var updatedPositions = notePositions
        updatedPositions[drumType] = position
        notePositions = updatedPositions
        saveSettings()
    }
    
    func resetToDefaults() {
        notePositions = Dictionary(uniqueKeysWithValues: DrumType.allCases.map { ($0, $0.notePosition) })
        saveSettings()
    }
}

// MARK: - Extensions

extension GameplayLayout.NotePosition {
    var displayName: String {
        switch self {
        // Extended positions above staff
        case .aboveLine9: return "Above Line 9"
        case .aboveLine8: return "Above Line 8"
        case .aboveLine7: return "Above Line 7"
        case .aboveLine6: return "Above Line 6"
        case .aboveLine5: return "Above Line 5"
        
        // Main staff positions
        case .line5: return "Line 5 (Top)"
        case .spaceBetween4And5: return "Space 4-5"
        case .line4: return "Line 4"
        case .spaceBetween3And4: return "Space 3-4"
        case .line3: return "Line 3 (Middle)"
        case .spaceBetween2And3: return "Space 2-3"
        case .line2: return "Line 2"
        case .spaceBetween1And2: return "Space 1-2"
        case .line1: return "Line 1 (Bottom)"
        
        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return "Below Space"
        case .belowLine1: return "Below Line 1"
        case .belowLine2: return "Below Line 2"
        case .belowLine3: return "Below Line 3"
        case .belowLine4: return "Below Line 4"
        case .belowLine5: return "Below Line 5"
        case .belowLine6: return "Below Line 6"
        }
    }
    
    var rawValue: String {
        switch self {
        // Extended positions above staff
        case .aboveLine9: return "aboveLine9"
        case .aboveLine8: return "aboveLine8"
        case .aboveLine7: return "aboveLine7"
        case .aboveLine6: return "aboveLine6"
        case .aboveLine5: return "aboveLine5"
        
        // Main staff positions
        case .line5: return "line5"
        case .spaceBetween4And5: return "spaceBetween4And5"
        case .line4: return "line4"
        case .spaceBetween3And4: return "spaceBetween3And4"
        case .line3: return "line3"
        case .spaceBetween2And3: return "spaceBetween2And3"
        case .line2: return "line2"
        case .spaceBetween1And2: return "spaceBetween1And2"
        case .line1: return "line1"
        
        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return "spaceBetweenLine1AndBelow"
        case .belowLine1: return "belowLine1"
        case .belowLine2: return "belowLine2"
        case .belowLine3: return "belowLine3"
        case .belowLine4: return "belowLine4"
        case .belowLine5: return "belowLine5"
        case .belowLine6: return "belowLine6"
        }
    }
    
    var previewOffset: CGFloat {
        switch self {
        // Extended positions above staff
        case .aboveLine9: return -72
        case .aboveLine8: return -64
        case .aboveLine7: return -56
        case .aboveLine6: return -48
        case .aboveLine5: return -40
        
        // Main staff positions
        case .line5: return -32
        case .spaceBetween4And5: return -28
        case .line4: return -24
        case .spaceBetween3And4: return -20
        case .line3: return -16
        case .spaceBetween2And3: return -12
        case .line2: return -8
        case .spaceBetween1And2: return -4
        case .line1: return 0
        
        // Extended positions below staff
        case .spaceBetweenLine1AndBelow: return 4
        case .belowLine1: return 8
        case .belowLine2: return 16
        case .belowLine3: return 24
        case .belowLine4: return 32
        case .belowLine5: return 40
        case .belowLine6: return 48
        }
    }
}

#Preview {
    NavigationStack {
        DrumNotationSettingsView()
    }
}
