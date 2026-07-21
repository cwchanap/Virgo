import Testing
@testable import Virgo

@Suite("Notation Layout Rest Tests")
struct NotationLayoutRestTests {
    private let support = NotationLayoutTestSupport()

    @Test("empty measure materializes one printed and one hidden full-measure rest")
    func emptyMeasureMaterializesFullMeasureRests() throws {
        let result = support.layout(notes: [])
        let upper = try #require(result.rests.first { $0.voice == .upper })
        let lower = try #require(result.rests.first { $0.voice == .lower })

        #expect(result.rests.count == 2)
        #expect(upper.duration == .fullMeasure)
        #expect(upper.durationTicks == result.tabGrid.ticksPerMeasure)
        #expect(upper.visibility == .printed)
        #expect(lower.duration == .fullMeasure)
        #expect(lower.durationTicks == result.tabGrid.ticksPerMeasure)
        #expect(lower.visibility == .hiddenDuplicate)
        #expect(upper.id.contains("m0"))
        #expect(upper.id.contains("vupper"))
        #expect(upper.id.contains("t0"))
        #expect(upper.id.contains("dfullMeasure"))
        #expect(upper.id.contains("xprinted"))
        #expect(upper.id.hasSuffix("-duplicate-0"))
    }

    @Test("single upper snare prints the lower full-measure companion")
    func upperSnarePrintsLowerFullMeasureRest() {
        let result = support.layout(notes: [
            Note(interval: .full, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ])

        #expect(result.rests.contains {
            $0.voice == .lower && $0.duration == .fullMeasure && $0.isPrinted
        })
        #expect(!result.rests.contains {
            $0.voice == .upper && $0.duration == .fullMeasure
        })
    }

    @Test("single lower kick prints the upper full-measure companion")
    func lowerKickPrintsUpperFullMeasureRest() {
        let result = support.layout(notes: [
            Note(interval: .full, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ])

        #expect(result.rests.contains {
            $0.voice == .upper && $0.duration == .fullMeasure && $0.isPrinted
        })
        #expect(!result.rests.contains {
            $0.voice == .lower && $0.duration == .fullMeasure
        })
    }

    @Test("active upper and lower voices receive independent internal rests")
    func activeVoicesReceiveIndependentInternalRests() {
        let result = support.layout(notes: [
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .bass, measureNumber: 1, measureOffset: 0.5)
        ])
        let upperPrinted = result.rests.filter { $0.voice == .upper && $0.isPrinted }
        let lowerPrinted = result.rests.filter { $0.voice == .lower && $0.isPrinted }

        #expect(upperPrinted.map(\.timeColumn.tickWithinMeasure) == [480])
        #expect(upperPrinted.map(\.duration) == [.half])
        #expect(lowerPrinted.map(\.timeColumn.tickWithinMeasure) == [0])
        #expect(lowerPrinted.map(\.duration) == [.half])
        #expect(!result.rests.contains { $0.duration == .fullMeasure })
    }

    @Test("full-measure rests use the measure midpoint but retain semantic tick zero")
    func fullMeasureRestUsesMeasureMidpoint() throws {
        let result = support.layout(notes: [])
        let measure = try #require(result.measures.first)
        let rest = try #require(result.rests.first { $0.isPrinted })

        #expect(rest.timeColumn.tickWithinMeasure == 0)
        #expect(rest.timeColumn.absoluteLayoutTick == 0)
        #expect(rest.position.x == measure.xOffset + measure.width / 2)
    }

    @Test("interval rests anchor to the exact tab-grid start column")
    func intervalRestUsesStartColumn() throws {
        let result = support.layout(notes: [
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0)
        ])
        let measure = try #require(result.measures.first)
        let rest = try #require(result.rests.first {
            $0.voice == .upper && $0.duration == .half && $0.isPrinted
        })

        #expect(rest.timeColumn.tickWithinMeasure == 480)
        #expect(rest.position.x == result.tabGrid.xPosition(in: measure, tickIndex: 480))
        #expect(rest.rhythmPosition == RhythmEventPosition(
            measureIndex: 0,
            localTick: 480,
            absoluteTick: 480
        ))
        #expect(rest.rhythm == NotationRhythm(baseInterval: .half))
        #expect(rest.tupletID == nil)
    }

    @Test("printed voice rests use distinct style-owned baselines")
    func printedRestsUseVoiceBaselines() throws {
        let style = NotationLayoutStyle.gameplayDefault
        let result = support.layout(notes: [
            Note(interval: .half, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .half, noteType: .bass, measureNumber: 1, measureOffset: 0)
        ], style: style)
        let upper = try #require(result.rests.first { $0.voice == .upper && $0.isPrinted })
        let lower = try #require(result.rests.first { $0.voice == .lower && $0.isPrinted })
        let staffLine3Y = GameplayLayout.StaffLinePosition.line3.absoluteY(for: 0)

        #expect(upper.position.y == staffLine3Y + style.upperVoiceRestOffset)
        #expect(lower.position.y == staffLine3Y + style.lowerVoiceRestOffset)
        #expect(upper.position.y != lower.position.y)
    }

    @Test("hidden rests stay in the layout without becoming printed content")
    func hiddenRestsRemainNonPrinted() throws {
        let result = support.layout(notes: [])
        let hidden = try #require(result.rests.first { $0.visibility == .hiddenDuplicate })

        #expect(!hidden.isPrinted)
        #expect(result.rests.contains(hidden))
        #expect(result.rests.filter(\.isPrinted).count == 1)
    }

    @Test("rest materialization leaves existing notation artifacts and content width note-driven")
    func restsDoNotFeedExistingArtifactBuilders() throws {
        let notes = [
            Note(interval: .eighth, noteType: .crash, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .snare, measureNumber: 1, measureOffset: 0.125),
            Note(interval: .quarter, noteType: .bass, measureNumber: 1, measureOffset: 0.5)
        ]
        let input = NotationLayoutInput(notes: notes, timeSignature: .fourFour)
        let engine = NotationLayoutEngine()
        let result = engine.layout(input: input)
        let measure = try #require(result.measures.first)
        let beamBuild = engine.buildBeams(
            noteHeads: result.noteHeads,
            tabGrid: result.tabGrid,
            timeSignature: input.timeSignature,
            style: input.style
        )
        let expectedStems = engine.buildStems(
            noteHeads: result.noteHeads, beams: beamBuild.beams, style: input.style
        )
        let expectedFlags = engine.buildFlags(
            noteHeads: result.noteHeads,
            beamBuild: beamBuild,
            stems: expectedStems,
            style: input.style
        )
        var resultWithoutRests = result
        resultWithoutRests.rests = []

        #expect(!result.rests.isEmpty)
        #expect(result.tabGrid == engine.buildTabGrid(notes: notes, input: input))
        #expect(result.measures == [RenderedMeasure(
            id: 0,
            measureIndex: 0,
            row: 0,
            xOffset: GameplayLayout.leftMargin,
            width: result.tabGrid.measureWidth,
            startTick: 0,
            durationTicks: result.tabGrid.ticksPerMeasure
        )])
        #expect(result.noteHeads.map(\.position.x) == [
            result.tabGrid.xPosition(in: measure, tickIndex: 0),
            result.tabGrid.xPosition(in: measure, tickIndex: 120),
            result.tabGrid.xPosition(in: measure, tickIndex: 480)
        ])
        #expect(result.beams == beamBuild.beams)
        #expect(Set(result.stems) == Set(expectedStems))
        #expect(Set(result.flags) == Set(expectedFlags))
        #expect(
            Set(result.ledgerLines)
                == Set(engine.buildLedgerLines(noteHeads: result.noteHeads, style: input.style))
        )
        #expect(Set(result.measureBars) == Set(engine.buildMeasureBars(measures: result.measures)))
        #expect(result.contentWidth == resultWithoutRests.contentWidth)
    }

    @Test("shuffled note input preserves rendered rest order and semantic IDs")
    func shuffledNotesPreserveRestOrderingAndIDs() {
        let notes = [
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0),
            Note(interval: .eighth, noteType: .bass, measureNumber: 1, measureOffset: 0.25),
            Note(interval: .quarter, noteType: .snare, measureNumber: 1, measureOffset: 0.75)
        ]
        let ordered = support.layout(notes: notes).rests
        let shuffled = support.layout(notes: [notes[2], notes[0], notes[1]]).rests

        #expect(!ordered.isEmpty)
        #expect(shuffled == ordered)
        #expect(shuffled.map(\.id) == ordered.map(\.id))
    }
}
