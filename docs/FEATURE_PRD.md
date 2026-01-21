# Virgo Feature Requirements Document (PRD)

> **Version:** 2.0
> **Date:** January 2026
> **Status:** Draft

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Practice & Learning Features](#1-practice--learning-features)
3. [Performance Tracking Features](#2-performance-tracking-features)
4. [Gamification Features](#3-gamification-features)
5. [Audio Enhancement Features](#4-audio-enhancement-features)
6. [Content Management Features](#5-content-management-features)
7. [Technical/Platform Features](#6-technicalplatform-features)
8. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

This document outlines 24 new features for Virgo, a SwiftUI-based drum notation and metronome application for iOS and macOS. Features are organized into six categories, each with detailed requirements focusing on **what** to build and **why** it matters to users.

---

## 1. Practice & Learning Features

### 1.1 Speed Control (Tempo Adjustment)

#### Overview
Allow users to slow down or speed up playback while maintaining proper audio pitch and timing relationships. Essential for learning complex patterns progressively.

#### Why This Matters
Beginners need to practice at slower tempos to build muscle memory and coordination. Advanced players use variable speed for challenging exercises. This is a fundamental feature for effective drum practice.

#### User Stories
- As a beginner, I want to slow down a difficult song to 50% speed so I can learn the pattern gradually
- As an intermediate player, I want to increase speed incrementally (75% → 100% → 110%) to build muscle memory
- As a user, I want the audio pitch to remain natural when I change tempo

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SC-01 | Support tempo scaling from 25% to 150% of original BPM | Must Have |
| SC-02 | Provide preset speed options: 50%, 75%, 100%, 125% | Must Have |
| SC-03 | Allow fine-grained speed adjustment via slider (5% increments) | Should Have |
| SC-04 | Display current effective BPM (original × scale factor) | Must Have |
| SC-05 | Preserve audio pitch when tempo changes (pitch-preserved time stretching) | Should Have |
| SC-06 | Remember last-used speed per song/chart | Could Have |

#### UI/UX Considerations
- Position tempo control near playback controls for easy access
- Show both percentage (75%) and effective BPM (90 BPM) for clarity
- Use horizontal slider with snap points at preset values (50%, 75%, 100%, 125%)
- Consider whether to allow real-time adjustment during playback or pause-only changes

#### Acceptance Criteria
- [ ] User can adjust tempo from 25% to 150%
- [ ] Metronome timing remains accurate at all speeds
- [ ] Input timing scoring adjusts correctly for scaled tempo
- [ ] BGM playback (if available) syncs with adjusted tempo
- [ ] UI clearly shows current tempo scale and effective BPM

#### Dependencies
- None

---

### 1.2 Section Loop Practice

#### Overview
Enable users to select specific measures or sections to loop repeatedly for focused practice on difficult passages.

#### Why This Matters
Concentrated practice on problem areas is more effective than repeatedly playing entire songs. Musicians universally use this technique to master difficult sections.

#### User Stories
- As a user, I want to select measures 8-12 to loop so I can master a difficult fill
- As a user, I want to set loop points visually on the notation
- As a user, I want the loop to transition smoothly without jarring stops

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SL-01 | Allow selection of loop start measure | Must Have |
| SL-02 | Allow selection of loop end measure | Must Have |
| SL-03 | Visual indication of selected loop region | Must Have |
| SL-04 | Smooth transition when loop restarts | Must Have |
| SL-05 | Quick presets: "Loop current measure", "Loop next 4 measures" | Should Have |
| SL-06 | Count-in before loop restart (optional) | Could Have |

#### UI/UX Considerations
- Highlight loop region with semi-transparent overlay on notation
- Provide drag handles to adjust loop start/end points
- Add toggle button to enable/disable loop without losing selection
- Show loop region indicator in progress bar
- Allow tap-to-set-start and tap-to-set-end as alternative to dragging

#### Acceptance Criteria
- [ ] User can select any contiguous range of measures to loop
- [ ] Playback seamlessly loops at boundaries
- [ ] Loop region is clearly visible on notation
- [ ] BGM syncs correctly when loop restarts
- [ ] Loop can be enabled/disabled during playback

#### Dependencies
- None

---

### 1.3 Count-In Feature

#### Overview
Add optional count-in beats before playback starts to help users prepare and find the tempo.

#### Why This Matters
Musicians need preparation time before playing. A count-in establishes the tempo and gives users time to position their hands/feet before the first note.

#### User Stories
- As a user, I want 4 count-in beats before the song starts so I can prepare
- As a user, I want to choose between 1, 2, or 4 bars of count-in
- As a user, I want to hear/feel the count-in through metronome clicks and haptics

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| CI-01 | Provide 1-bar, 2-bar, and 4-bar count-in options | Must Have |
| CI-02 | Play metronome clicks during count-in | Must Have |
| CI-03 | Display visual countdown (4, 3, 2, 1) | Must Have |
| CI-04 | Haptic feedback during count-in (iOS) | Should Have |
| CI-05 | Option to disable count-in | Must Have |
| CI-06 | Remember count-in preference | Should Have |

#### UI/UX Considerations
- Display large, centered countdown numbers as overlay
- Animate numbers with scale/fade transitions
- Emphasize metronome accent on beat 1 of each count-in bar
- Make settings accessible from both settings menu and gameplay view
- Dim the notation slightly during count-in to indicate "not started yet"

#### Acceptance Criteria
- [ ] Count-in plays correct number of bars before song starts
- [ ] Visual countdown displays clearly
- [ ] Metronome clicks are audible during count-in
- [ ] Haptic feedback works on iOS
- [ ] Count-in preference persists across sessions

#### Dependencies
- None

---

### 1.4 Isolated Track Practice

#### Overview
Allow users to isolate and practice specific drum voices (e.g., hi-hat only, kick/snare only) to develop coordination by focusing on one element at a time.

#### Why This Matters
Developing independence between limbs is a core drumming skill. Practicing hands and feet separately before combining them is a proven teaching method.

#### User Stories
- As a beginner, I want to practice just the kick drum part first
- As a user, I want to isolate hi-hat patterns to focus on timing
- As a user, I want to combine multiple voices (kick + snare) while muting others

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| IT-01 | Toggle visibility/scoring for each drum type | Must Have |
| IT-02 | Show muted notes in faded/ghost style | Should Have |
| IT-03 | Input scoring only counts enabled drum types | Must Have |
| IT-04 | Quick presets: "Hands only", "Feet only", "All" | Should Have |
| IT-05 | Remember isolation settings per chart | Could Have |

#### UI/UX Considerations
- Display drum type toggles in a collapsible panel to save screen space
- Use color-coded icons for each drum type
- Render muted notes at 30% opacity to maintain visual context
- Provide quick preset buttons for common combinations (hands/feet/kick-snare/all)
- Show active filter count indicator (e.g., "3 of 10 drums")

#### Acceptance Criteria
- [ ] Individual drum types can be toggled on/off
- [ ] Only enabled drums appear in notation (or appear muted)
- [ ] Input scoring ignores disabled drum types
- [ ] Presets work correctly
- [ ] Visual distinction clear between enabled and disabled notes

#### Dependencies
- None

---

### 1.5 Progressive Difficulty Training

#### Overview
Automatically simplify complex patterns by removing notes while maintaining the rhythmic framework, then gradually restore notes as the user improves.

#### Why This Matters
Learning complex patterns all at once is overwhelming. Scaffolded learning with gradual complexity increase is pedagogically sound and prevents frustration.

#### User Stories
- As a beginner, I want to start with just the basic beat (kick/snare) and add complexity
- As a user, I want the app to suggest when I'm ready for more notes
- As a user, I want to manually adjust the difficulty level

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| PD-01 | Difficulty levels from 1 (simplest) to 5 (full chart) | Must Have |
| PD-02 | Level 1: Kick and snare on main beats only | Must Have |
| PD-03 | Level 2: Add hi-hat pattern | Must Have |
| PD-04 | Level 3: Add toms and cymbals | Must Have |
| PD-05 | Level 4: Add off-beat notes | Should Have |
| PD-06 | Level 5: Full original chart | Must Have |
| PD-07 | Suggest difficulty increase when accuracy > 90% | Should Have |

#### UI/UX Considerations
- Use horizontal difficulty slider (1-5) or stepper
- Display visual indicator showing how many notes are filtered vs total
- Show toast notification when suggesting difficulty increase
- Optionally show "ghost" notes for filtered-out content to preview next level
- Animate difficulty level changes smoothly

#### Acceptance Criteria
- [ ] 5 distinct difficulty levels with appropriate note filtering
- [ ] Notes filter correctly based on rhythmic importance
- [ ] User can manually adjust difficulty during playback
- [ ] Accuracy tracking suggests when to increase difficulty
- [ ] Smooth transition between difficulty levels

#### Dependencies
- Session Statistics (2.1) for accuracy tracking

---

## 2. Performance Tracking Features

### 2.1 Session Statistics

#### Overview
Track detailed performance metrics during practice sessions including accuracy percentage, perfect/great/good/miss counts, and timing deviation patterns.

#### Why This Matters
"What gets measured gets improved." Objective feedback helps users understand their performance and track improvement. This transforms casual practice into deliberate, measurable improvement.

#### User Stories
- As a user, I want to see my accuracy percentage after each session
- As a user, I want to know how many Perfect vs Good hits I got
- As a user, I want to understand my timing tendencies (early/late)

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SS-01 | Track total notes, hits, and misses per session | Must Have |
| SS-02 | Calculate accuracy percentage | Must Have |
| SS-03 | Count Perfect/Great/Good/Miss breakdown | Must Have |
| SS-04 | Track average timing deviation (ms) | Should Have |
| SS-05 | Show early vs late tendency | Should Have |
| SS-06 | Display results screen after session | Must Have |

#### UI/UX Considerations
- Results screen appears after song completion or manual end
- Use circular progress indicator for accuracy percentage
- Display bar chart for Perfect/Great/Good/Miss distribution
- Show timing deviation as histogram or average with direction indicator
- Allow dismissing results or saving/sharing

#### Acceptance Criteria
- [ ] All note interactions are tracked during session
- [ ] Accuracy percentage calculates correctly
- [ ] Breakdown by accuracy tier is accurate
- [ ] Timing deviation statistics are meaningful
- [ ] Results screen displays after session ends

#### Dependencies
- Input system already provides timing data

---

### 2.2 Historical Progress Tracking

#### Overview
Store performance history across sessions and visualize improvement over time with charts and graphs.

#### Why This Matters
Seeing tangible progress over days and weeks is highly motivating. Historical data identifies patterns and validates the user's practice efforts.

#### User Stories
- As a user, I want to see how my accuracy has improved over the past month
- As a user, I want to track my progress on specific songs
- As a user, I want to see my total practice time

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| HP-01 | Persist session statistics to database | Must Have |
| HP-02 | Display accuracy trend chart (line graph) | Must Have |
| HP-03 | Show per-song progress history | Should Have |
| HP-04 | Track total practice time | Should Have |
| HP-05 | Weekly/monthly summary statistics | Should Have |
| HP-06 | Export progress data | Could Have |

#### UI/UX Considerations
- Use Swift Charts framework for visualizations
- Display line chart for accuracy trend over time
- Show calendar heat map for practice frequency
- Create summary cards for key metrics (total time, avg accuracy, etc.)
- Allow filtering by date range and song

#### Acceptance Criteria
- [ ] Sessions persist across app launches
- [ ] Accuracy trend chart displays correctly
- [ ] Per-song history is accessible
- [ ] Total practice time accumulates correctly
- [ ] Data survives app updates

#### Dependencies
- Session Statistics (2.1)

---

### 2.3 Problem Area Identification

#### Overview
Automatically identify specific note patterns, drum types, or rhythmic subdivisions where the user consistently struggles.

#### Why This Matters
Users often don't realize their specific weaknesses. Automated analysis provides objective insights and directs practice efforts efficiently.

#### User Stories
- As a user, I want to know which drum type I miss most often
- As a user, I want to identify which measure positions are hardest
- As a user, I want practice recommendations based on my weaknesses

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| PA-01 | Track miss rate by drum type | Must Have |
| PA-02 | Track miss rate by rhythmic position (downbeat, offbeat, etc.) | Should Have |
| PA-03 | Identify problematic measure ranges | Should Have |
| PA-04 | Generate practice recommendations | Should Have |
| PA-05 | Highlight problem areas in notation | Could Have |

#### UI/UX Considerations
- Display problem areas in session results view
- Use color-coded visualization (red = high miss rate)
- Provide actionable recommendations like "Practice hi-hat isolation" or "Loop measures 8-12"
- Show improvement over time for problem areas
- Make recommendations tappable to jump directly to suggested practice mode

#### Acceptance Criteria
- [ ] Miss rates calculated per drum type
- [ ] Problematic measures identified correctly
- [ ] Recommendations generated based on data
- [ ] Analysis updates across sessions

#### Dependencies
- Session Statistics (2.1)
- Historical Progress Tracking (2.2)

---

### 2.4 Timing Deviation Visualization

#### Overview
Show graphical representation of timing accuracy (early/late tendencies) overlaid on the score after practice.

#### Why This Matters
Systematic timing issues (always early or late) are hard to self-diagnose. Visual feedback makes timing patterns obvious and actionable.

#### User Stories
- As a user, I want to see exactly where I hit early or late
- As a user, I want to understand my systematic timing bias
- As a user, I want to see timing deviation on a per-note basis

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| TD-01 | Record timing deviation for each hit | Must Have |
| TD-02 | Display timing histogram (early/on-time/late distribution) | Must Have |
| TD-03 | Show timing deviation overlay on notation | Should Have |
| TD-04 | Calculate and display average deviation | Must Have |
| TD-05 | Color-code notes by timing (green=perfect, yellow=early/late) | Should Have |

#### UI/UX Considerations
- Use histogram with bins for timing ranges (<-50ms, -50 to -25, etc.)
- Color-code histogram bars (blue=early, green=on-time, orange=late)
- Optionally overlay timing indicators on notation view
- Show average deviation prominently with direction indicator
- Use Swift Charts for visualization

#### Acceptance Criteria
- [ ] Timing deviation recorded for every hit
- [ ] Histogram displays deviation distribution correctly
- [ ] Color-coded timing feedback visible
- [ ] Average deviation clearly shown

#### Dependencies
- Session Statistics (2.1)

---

## 3. Gamification Features

### 3.1 Achievement System

#### Overview
Implement badges and achievements for milestones like total practice time, songs completed, accuracy streaks, and more.

#### Why This Matters
Achievements provide extrinsic motivation and create intermediate goals. They make practice feel rewarding beyond skill improvement alone.

#### User Stories
- As a user, I want to earn badges for reaching practice milestones
- As a user, I want to see my achievement progress
- As a user, I want notifications when I unlock achievements

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| AC-01 | Define achievement categories and criteria | Must Have |
| AC-02 | Track achievement progress | Must Have |
| AC-03 | Persist unlocked achievements | Must Have |
| AC-04 | Display achievement gallery in profile | Must Have |
| AC-05 | Show unlock notification | Should Have |
| AC-06 | Share achievements (optional) | Could Have |

#### Achievement Categories
- **Practice Milestones**: First session, 10 hours, 50 hours, 100 hours
- **Accuracy**: Perfect song, 90%+ accuracy, 10-song streak
- **Collection**: 5 songs, 20 songs, all difficulties
- **Skill**: Expert chart completion, 100 combo, specific techniques

#### UI/UX Considerations
- Display achievement gallery as grid of icons (locked/unlocked states)
- Show progress bars for partially completed achievements
- Use toast notification with animation on unlock
- Include achievement title, description, and unlock date
- Badge designs should be visually appealing and distinct

#### Acceptance Criteria
- [ ] Multiple achievement categories defined
- [ ] Progress tracks correctly
- [ ] Achievements persist after unlock
- [ ] Gallery displays all achievements with locked/unlocked states
- [ ] Notification appears on unlock

#### Dependencies
- Historical Progress Tracking (2.2)

---

### 3.2 Combo System and Scoring

#### Overview
Implement combo multipliers for consecutive accurate hits and a comprehensive scoring system.

#### Why This Matters
Real-time scoring and combos add immediate gratification and game-like engagement to practice. Competing for high scores motivates repeated practice.

#### User Stories
- As a user, I want to build combos by hitting notes accurately
- As a user, I want to see my score increase in real-time
- As a user, I want to compete for high scores

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| CS-01 | Track consecutive hit combo | Must Have |
| CS-02 | Combo multiplier increases score | Must Have |
| CS-03 | Display current combo count | Must Have |
| CS-04 | Show score in real-time | Must Have |
| CS-05 | Store high score per chart | Should Have |
| CS-06 | Combo break feedback (visual/haptic) | Should Have |

#### Scoring Rules
- Base score: 100 points per note
- Accuracy multiplier: Perfect (1.0x), Great (0.8x), Good (0.5x), Miss (0x)
- Combo multiplier tiers:
  - 1-9 combo: 1.0x
  - 10-24 combo: 1.5x
  - 25-49 combo: 2.0x
  - 50-99 combo: 2.5x
  - 100+ combo: 3.0x

#### UI/UX Considerations
- Display score in top corner
- Show combo counter with animated numbers
- Provide visual feedback on combo milestones (10, 25, 50, 100)
- Flash screen or shake on combo break
- Animate score increase on each hit
- Show high score comparison during gameplay

#### Acceptance Criteria
- [ ] Combo increments on successful hits
- [ ] Combo breaks on miss
- [ ] Score calculates correctly with multipliers
- [ ] High scores persist per chart
- [ ] Visual feedback for combo milestones

#### Dependencies
- None

---

### 3.3 Daily Challenges

#### Overview
Present daily rotating challenges like "achieve 90% accuracy on any Expert chart" or "practice for 30 minutes total."

#### Why This Matters
Daily goals create habit-forming routines. Variety prevents boredom and encourages exploring different aspects of practice.

#### User Stories
- As a user, I want daily goals to motivate my practice
- As a user, I want variety in my practice through challenges
- As a user, I want rewards for completing challenges

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| DC-01 | Generate daily challenge at midnight | Must Have |
| DC-02 | Display current challenge on home screen | Must Have |
| DC-03 | Track challenge progress | Must Have |
| DC-04 | Mark challenge complete and reward | Must Have |
| DC-05 | Challenge history | Should Have |
| DC-06 | Multiple challenge tiers (easy/medium/hard) | Could Have |

#### Challenge Types
- **Accuracy goals**: "Achieve 90% accuracy on any song"
- **Practice duration**: "Practice for 30 minutes today"
- **Song completion**: "Complete 5 different songs"
- **Streak goals**: "Hit 20 perfect notes in a row"
- **Difficulty targets**: "Play 3 Expert charts"

#### UI/UX Considerations
- Display challenge card prominently on home screen
- Show progress bar toward completion
- Use checkmark animation when completed
- Provide reward feedback (points, badge, etc.)
- Allow viewing past challenges and completion rate

#### Acceptance Criteria
- [ ] New challenge generates daily at midnight
- [ ] Challenge progress tracks correctly
- [ ] Completion detected and rewarded
- [ ] Challenge visible on main screen
- [ ] Challenges reset at midnight local time

#### Dependencies
- Session Statistics (2.1)

---

### 3.4 Skill Rating System

#### Overview
Calculate and display a player skill rating based on performance across different difficulty levels.

#### Why This Matters
A single, comparable number makes progress tangible. Skill rating enables difficulty recommendations and social comparison.

#### User Stories
- As a user, I want a single number representing my skill level
- As a user, I want to see my rating improve as I practice
- As a user, I want skill-appropriate song recommendations

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SR-01 | Calculate skill rating (0-100 scale) | Must Have |
| SR-02 | Update rating after each session | Must Have |
| SR-03 | Display rating in profile | Must Have |
| SR-04 | Show rating trend over time | Should Have |
| SR-05 | Recommend songs based on rating | Should Have |

#### Rating Calculation
- Use ELO-style rating system
- Factor in: chart difficulty level, accuracy, timing consistency
- Increase rating on good performance relative to chart difficulty
- Decrease rating on poor performance
- Stabilize over time (fewer swings after many sessions)

#### UI/UX Considerations
- Display rating prominently in profile (large number with label)
- Show rating change after session (+3, -1, etc.)
- Graph rating history over time
- Use rating to filter/sort song library
- Provide rating ranges for song recommendations

#### Acceptance Criteria
- [ ] Skill rating calculates based on performance
- [ ] Rating updates after sessions
- [ ] Rating visible in profile
- [ ] Recommendations use rating appropriately

#### Dependencies
- Session Statistics (2.1)
- Historical Progress Tracking (2.2)

---

## 4. Audio Enhancement Features

### 4.1 Hit Feedback Sounds

#### Overview
Play drum sound samples when user hits correct notes, creating a more immersive experience.

#### Why This Matters
Audio feedback creates immediate satisfaction and reinforces correct timing. Makes silent practice more engaging and helps users hear what they're playing.

#### User Stories
- As a user, I want to hear drum sounds when I hit notes
- As a user, I want the feedback to be instant and satisfying
- As a user, I want to adjust or disable feedback sounds

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| HF-01 | Play drum sample on successful hit | Must Have |
| HF-02 | Support all drum types (kick, snare, hi-hat, etc.) | Must Have |
| HF-03 | Low-latency playback (<10ms) | Must Have |
| HF-04 | Volume control for feedback sounds | Should Have |
| HF-05 | Option to disable feedback | Must Have |
| HF-06 | Different sounds based on velocity | Could Have |

#### Audio Requirements
- Drum sample sounds needed for: kick, snare, hi-hat, crash, ride, tom1, tom2, tom3, cowbell
- Samples should be short (<500ms), high-quality
- Consistent volume levels across samples

#### UI/UX Considerations
- Feedback volume slider in audio settings
- Master enable/disable toggle
- Latency must be imperceptible to maintain timing feel
- Samples should sound realistic but not overpower metronome/BGM

#### Acceptance Criteria
- [ ] Drum samples play on successful hits
- [ ] Latency is imperceptible (<10ms)
- [ ] All drum types have distinct sounds
- [ ] Volume is adjustable
- [ ] Feedback can be disabled

#### Dependencies
- None

---

### 4.2 Audio Latency Calibration

#### Overview
Provide a calibration tool to measure and compensate for audio output latency.

#### Why This Matters
Bluetooth headphones and different audio interfaces introduce latency. Without calibration, timing scores are inaccurate, frustrating users.

#### User Stories
- As a user with Bluetooth headphones, I want to calibrate for audio delay
- As a user, I want my timing scores to be accurate regardless of audio setup
- As a user, I want a simple calibration process

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| LC-01 | Provide tap-to-beat calibration workflow | Must Have |
| LC-02 | Calculate average latency offset | Must Have |
| LC-03 | Store calibration in settings | Must Have |
| LC-04 | Apply offset to timing calculations | Must Have |
| LC-05 | Allow manual offset adjustment | Should Have |
| LC-06 | Support different calibration per audio output | Could Have |

#### Calibration Process
1. User starts calibration
2. Metronome plays steady beat (120 BPM)
3. User taps in sync with metronome (16 taps)
4. System calculates average timing deviation
5. Offset is saved and applied to future scoring

#### UI/UX Considerations
- Simple tap-along interface with visual metronome
- Progress indicator showing taps remaining (e.g., "12 of 16")
- Display calculated offset in milliseconds after calibration
- Option to re-calibrate or manually adjust by ±100ms
- Explanation of why calibration is needed

#### Acceptance Criteria
- [ ] Calibration workflow is intuitive
- [ ] Latency offset calculates correctly
- [ ] Offset persists across sessions
- [ ] Timing scoring uses calibrated offset
- [ ] Manual adjustment available

#### Dependencies
- None

---

### 4.3 Custom Metronome Sounds

#### Overview
Allow users to choose from different metronome click sounds or import custom sounds.

#### Why This Matters
Personal preference varies widely for metronome sounds. Reducing auditory fatigue by offering variety improves practice experience.

#### User Stories
- As a user, I want to choose a metronome sound I like
- As a user, I want different sounds for accents vs regular beats
- As a user, I want to preview sounds before selecting

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| MS-01 | Provide 3-5 built-in click sound options | Must Have |
| MS-02 | Preview sounds in settings | Must Have |
| MS-03 | Different sounds for accent vs normal beat | Should Have |
| MS-04 | Persist sound selection | Must Have |

#### Sound Options
- **Classic**: Traditional metronome beep (high/low tones)
- **Wood Block**: Natural percussion sound
- **Hi-Hat**: Drum kit sound
- **Rimshot**: Snare rim sound
- **Digital**: Electronic beep

#### UI/UX Considerations
- Display sound options as list with preview buttons
- Clearly label accent vs normal beat sounds
- Show current selection with checkmark
- Preview plays both accent and normal beat in sequence
- Consider grouping sounds by character (organic, electronic, etc.)

#### Acceptance Criteria
- [ ] Multiple sound options available
- [ ] Preview plays selected sound
- [ ] Selection persists across sessions
- [ ] Both accent and normal sounds change with selection

#### Dependencies
- None

---

### 4.4 Independent Volume Controls

#### Overview
Separate volume controls for BGM, metronome, and drum hit feedback.

#### Why This Matters
Different practice contexts require different audio mixes. Users might want loud metronome with quiet BGM, or vice versa.

#### User Stories
- As a user, I want to lower the BGM to hear my hits better
- As a user, I want to mute the metronome but keep other audio
- As a user, I want presets for different practice modes

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| VC-01 | Independent volume slider for BGM | Must Have |
| VC-02 | Independent volume slider for metronome | Must Have |
| VC-03 | Independent volume slider for hit feedback | Must Have |
| VC-04 | Master volume control | Should Have |
| VC-05 | Mute toggles for each channel | Should Have |
| VC-06 | Volume presets | Could Have |

#### Volume Presets
- **Balanced**: All at 70%
- **Practice**: BGM 50%, Metronome 100%, Feedback 80%
- **Performance**: BGM 80%, Metronome 30%, Feedback 100%

#### UI/UX Considerations
- Group sliders in audio settings section
- Use consistent slider design across all three channels
- Display percentage values alongside sliders
- Add mute button (speaker icon) for quick toggles
- Preset buttons for quick switching
- Changes take effect immediately

#### Acceptance Criteria
- [ ] Three independent volume controls function correctly
- [ ] Master volume affects all channels proportionally
- [ ] Settings persist across sessions
- [ ] Audio levels update in real-time during playback

#### Dependencies
- Hit Feedback Sounds (4.1)

---

## 5. Content Management Features

### 5.1 Favorites System

#### Overview
Allow users to bookmark songs and charts for quick access.

#### Why This Matters
Users have favorite songs they practice repeatedly. Quick access reduces friction and improves the practice workflow.

#### User Stories
- As a user, I want to favorite songs I practice often
- As a user, I want to filter to show only favorites
- As a user, I want to quickly toggle favorite status

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FV-01 | Toggle favorite status on any song | Must Have |
| FV-02 | Display favorite indicator on song rows | Must Have |
| FV-03 | Filter to show only favorites | Must Have |
| FV-04 | Sort favorites to top of list | Should Have |
| FV-05 | Favorites section in library | Should Have |

#### UI/UX Considerations
- Heart icon button to toggle favorite status
- Filled heart for favorited, outline for not favorited
- Favorites filter toggle in library toolbar
- Option to sort: "Favorites first" or "All songs alphabetically"
- Swipe action for quick favorite/unfavorite

#### Acceptance Criteria
- [ ] Favorite toggle works on song rows
- [ ] Visual indicator shows favorite status clearly
- [ ] Favorites filter functions correctly
- [ ] Favorites persist across app launches

#### Dependencies
- None

---

### 5.2 Smart Playlists

#### Overview
Allow users to create and save playlists of songs for structured practice sessions.

#### Why This Matters
Structured practice routines are more effective than random selection. Playlists support warmup routines, progressive difficulty, and focused genre practice.

#### User Stories
- As a user, I want to create a playlist for my warmup routine
- As a user, I want continuous playback through a playlist
- As a user, I want to reorder songs in my playlist

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| PL-01 | Create named playlists | Must Have |
| PL-02 | Add/remove songs from playlists | Must Have |
| PL-03 | Reorder songs within playlist | Should Have |
| PL-04 | Continuous playback mode | Should Have |
| PL-05 | Smart playlists (auto-generated by criteria) | Could Have |

#### Playlist Features
- Manual playlists: User curates song list
- Smart playlists: Auto-populate based on criteria (e.g., "All Easy difficulty", "BPM 120-140")
- Shuffle option
- Loop entire playlist option

#### UI/UX Considerations
- Playlists section in library
- Drag-and-drop reordering
- Add to playlist from song context menu
- Display playlist duration and song count
- Icon to distinguish manual vs smart playlists

#### Acceptance Criteria
- [ ] Playlists can be created and named
- [ ] Songs can be added/removed
- [ ] Song order can be changed via drag-and-drop
- [ ] Playlists persist across sessions

#### Dependencies
- None

---

### 5.3 Advanced Search and Filtering

#### Overview
Enhanced search with filters for BPM range, difficulty, genre, duration, and recently played.

#### Why This Matters
Large song libraries become hard to navigate. Powerful filtering helps users find appropriate content quickly.

#### User Stories
- As a user, I want to find songs within a specific BPM range
- As a user, I want to filter by difficulty level
- As a user, I want to combine multiple filters

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SF-01 | Search by title and artist | Must Have |
| SF-02 | Filter by BPM range | Should Have |
| SF-03 | Filter by difficulty | Should Have |
| SF-04 | Filter by genre | Should Have |
| SF-05 | Combine multiple filters | Should Have |
| SF-06 | Save filter presets | Could Have |

#### Filter Options
- **Text search**: Title, artist (fuzzy matching)
- **BPM range**: Slider with min/max
- **Difficulty**: Multi-select checkboxes (Easy, Medium, Hard, Expert)
- **Genre**: Multi-select from available genres
- **Duration**: Range slider (1-10 minutes)
- **Recently played**: Toggle

#### UI/UX Considerations
- Filter sheet/panel with all options
- Active filters shown as removable chips
- "Clear all filters" button
- Results count displayed
- Filters persist during session
- Search happens as user types (debounced)

#### Acceptance Criteria
- [ ] Text search works on title and artist
- [ ] BPM range filter works correctly
- [ ] Difficulty filter works correctly
- [ ] Multiple filters combine with AND logic
- [ ] Results update in real-time

#### Dependencies
- None

---

### 5.4 Custom Chart Editor

#### Overview
Allow users to create their own drum charts for any audio file.

#### Why This Matters
Expands content beyond server library. Enables users to practice any song they want. Community-created content increases engagement.

#### User Stories
- As a user, I want to create a chart for my favorite song
- As a user, I want to tap along to place notes
- As a user, I want to edit and refine my charts

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| CE-01 | Import audio file from device | Must Have |
| CE-02 | Set BPM and time signature | Must Have |
| CE-03 | Tap-to-place notes during playback | Must Have |
| CE-04 | Edit note positions after recording | Should Have |
| CE-05 | Delete individual notes | Must Have |
| CE-06 | Save chart to local library | Must Have |
| CE-07 | Export chart as DTX file | Could Have |

#### Editor Features
- Import audio from Files app
- Auto-detect BPM (optional AI feature)
- Record mode: Play audio and tap to place notes
- Edit mode: Visual timeline with draggable notes
- Playback preview
- Undo/redo support

#### UI/UX Considerations
- Waveform visualization for reference
- Drum pad interface for recording
- Timeline with measure markers
- Snap-to-grid option for precise placement
- Color-code notes by drum type
- Quick access to drum type selection

#### Acceptance Criteria
- [ ] Audio files can be imported from device
- [ ] BPM and time signature are configurable
- [ ] Notes record during playback
- [ ] Notes can be edited/deleted after recording
- [ ] Chart saves to library and appears in song list

#### Dependencies
- None

---

## 6. Technical/Platform Features

### 6.1 iCloud Sync

#### Overview
Synchronize progress, favorites, and settings across devices using CloudKit.

#### Why This Matters
Users expect seamless experiences across iPhone, iPad, and Mac. Losing progress when switching devices is frustrating.

#### User Stories
- As a user, I want my progress on iPhone to appear on iPad
- As a user, I want my favorites synced across devices
- As a user, I want to control what syncs

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| IC-01 | Sync practice history | Must Have |
| IC-02 | Sync achievements | Must Have |
| IC-03 | Sync favorites | Must Have |
| IC-04 | Sync settings/preferences | Should Have |
| IC-05 | Conflict resolution (last-write-wins) | Must Have |
| IC-06 | Sync status indicator | Should Have |

#### Sync Scope
- **Synced**: Practice sessions, achievements, favorites, high scores, settings, playlists
- **Not synced**: Downloaded audio files, cached server data
- **Optional sync**: Custom charts (large data)

#### UI/UX Considerations
- Settings toggle to enable/disable iCloud sync
- Sync status indicator (syncing/synced/error)
- Last sync timestamp
- Conflict resolution: newest data wins
- Sync happens automatically in background
- Manual "Sync Now" button

#### Acceptance Criteria
- [ ] Practice history syncs across devices
- [ ] Achievements sync correctly
- [ ] Favorites sync correctly
- [ ] Conflicts resolve gracefully
- [ ] User can enable/disable sync
- [ ] Sync errors are reported to user

#### Dependencies
- Historical Progress Tracking (2.2)
- Achievement System (3.1)

---

### 6.2 iPad Optimization

#### Overview
Enhanced UI layouts optimized for iPad screen sizes with side-by-side views and better use of screen space.

#### Why This Matters
iPad users deserve experiences tailored to larger screens. Underutilized screen space feels like a wasted opportunity.

#### User Stories
- As an iPad user, I want to use the larger screen effectively
- As an iPad user, I want split view support
- As an iPad user, I want to see more measures at once in gameplay

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| IP-01 | Adaptive layouts for iPad | Must Have |
| IP-02 | Split view navigation (sidebar + content + detail) | Should Have |
| IP-03 | More measures visible in gameplay | Should Have |
| IP-04 | Landscape orientation optimization | Should Have |
| IP-05 | Pointer/trackpad support | Could Have |

#### iPad-Specific Enhancements
- Navigation: Sidebar (library/settings) + Song list + Gameplay detail
- Gameplay: 6 measures per row instead of 4
- Settings: Two-column layout
- Statistics: Side-by-side chart comparisons
- Larger touch targets appropriate for pointer use

#### UI/UX Considerations
- Use NavigationSplitView for three-column layout
- Collapsible sidebar
- Adaptive font sizes and spacing
- Landscape should be fully functional (not locked to portrait)
- Utilize extra space for context, not just bigger fonts

#### Acceptance Criteria
- [ ] iPad uses split view layout
- [ ] More content visible on larger screens
- [ ] Landscape orientation works well
- [ ] All features accessible on iPad
- [ ] App feels native to iPad, not stretched iPhone app

#### Dependencies
- None

---

### 6.3 Apple Watch Companion

#### Overview
Simple metronome functionality on Apple Watch with haptic feedback for practice without phone.

#### Why This Matters
Drummers may want a minimalist metronome on their wrist without pulling out phone/iPad. Useful for acoustic practice sessions.

#### User Stories
- As a user, I want a metronome on my wrist
- As a user, I want haptic feedback for beats
- As a user, I want quick BPM adjustment on Watch

#### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| AW-01 | Basic metronome with BPM control | Must Have |
| AW-02 | Haptic feedback on beats | Must Have |
| AW-03 | Accent on beat 1 | Should Have |
| AW-04 | Time signature selection | Should Have |
| AW-05 | Sync settings with iPhone app | Could Have |

#### Watch App Features
- Standalone metronome (works without iPhone nearby)
- BPM: 40-200
- Digital Crown for BPM adjustment
- Large start/stop button
- Time signatures: 4/4, 3/4, 6/8
- Haptic patterns: Strong tap on beat 1, light tap on other beats

#### UI/UX Considerations
- Minimal UI optimized for glanceable use
- Large, tappable controls
- Current BPM displayed prominently
- Beat indicator animation
- Low power consumption for extended practice sessions
- Complication for quick access

#### Acceptance Criteria
- [ ] Metronome functions independently on Watch
- [ ] Haptic feedback on beats (stronger on beat 1)
- [ ] BPM adjustable via Digital Crown
- [ ] Time signature selectable
- [ ] App launches quickly

#### Dependencies
- None

---

## Implementation Roadmap

### Priority Framework
Features are prioritized based on:
- **User Impact**: How much value does this provide?
- **Effort**: How complex is implementation?
- **Dependencies**: What must be built first?
- **Strategic Value**: Does this differentiate Virgo?

### Phase 1: Core Practice Enhancement (Months 1-2)
**Goal**: Improve immediate practice experience with quick wins

1. **Speed Control** (1.1) - Essential for learning
2. **Count-In Feature** (1.3) - Small effort, high value
3. **Session Statistics** (2.1) - Foundation for all tracking
4. **Favorites System** (5.1) - Quick content organization win

**Success Metrics**: 30% of users use speed control, 50% use count-in, session stats viewed after 70% of sessions

---

### Phase 2: Engagement & Retention (Months 2-3)
**Goal**: Add gamification and feedback to increase engagement

5. **Section Loop Practice** (1.2) - Critical for effective practice
6. **Audio Latency Calibration** (4.2) - Fixes accuracy frustration
7. **Achievement System** (3.1) - Long-term motivation
8. **Combo System and Scoring** (3.2) - Immediate engagement

**Success Metrics**: 25% increase in session length, 40% of users unlock achievements

---

### Phase 3: Advanced Practice Tools (Months 3-4)
**Goal**: Provide sophisticated tools for serious learners

9. **Isolated Track Practice** (1.4) - Coordination building
10. **Progressive Difficulty Training** (1.5) - Scaffolded learning
11. **Hit Feedback Sounds** (4.1) - Enhanced practice feel
12. **Historical Progress Tracking** (2.2) - Long-term motivation

**Success Metrics**: 20% of users use isolation features, progress tracking viewed weekly by 60% of users

---

### Phase 4: Content & Intelligence (Months 4-5)
**Goal**: Smart features and better content management

13. **Advanced Search and Filtering** (5.3) - Better discoverability
14. **Smart Playlists** (5.2) - Structured practice
15. **Problem Area Identification** (2.3) - Personalized guidance
16. **Daily Challenges** (3.3) - Daily engagement hook

**Success Metrics**: 40% of users create playlists, 50% complete daily challenges

---

### Phase 5: Platform Expansion (Months 5-6)
**Goal**: Expand platform reach and sync capabilities

17. **iPad Optimization** (6.2) - Capture tablet market
18. **iCloud Sync** (6.1) - Seamless multi-device
19. **Custom Metronome Sounds** (4.3) - Personalization
20. **Independent Volume Controls** (4.4) - Audio mixing flexibility

**Success Metrics**: 15% iPad market share, 70% of multi-device users enable sync

---

### Phase 6: Advanced Features (Months 6+)
**Goal**: Differentiate with unique, advanced capabilities

21. **Timing Deviation Visualization** (2.4) - Advanced analytics
22. **Skill Rating System** (3.4) - Comparable progression
23. **Custom Chart Editor** (5.4) - User-generated content
24. **Apple Watch Companion** (6.3) - Wearable expansion

**Success Metrics**: 10% of users create custom charts, 5% use Watch app regularly

---

## Appendix

### A. Glossary
- **BPM**: Beats Per Minute - tempo measurement
- **Chart**: A specific difficulty arrangement of a song
- **Combo**: Consecutive successful note hits without a miss
- **DTX**: DTXMania file format for drum notation charts
- **Measure**: A musical bar containing a fixed number of beats
- **Time Signature**: Musical notation indicating beats per measure (e.g., 4/4)

### B. Success Metrics Framework

Each feature should track:
- **Adoption Rate**: % of active users who use the feature
- **Engagement Depth**: Frequency of use among adopters
- **Impact on Retention**: Effect on 7-day and 30-day retention
- **User Satisfaction**: Feature rating in app store reviews/feedback

### C. Design Principles

All features should adhere to:
1. **Immediate Feedback**: Users see/hear results of actions instantly
2. **Progressive Disclosure**: Simple by default, complexity available when needed
3. **Undo/Redo**: Destructive actions can be reversed
4. **Accessibility**: VoiceOver support, Dynamic Type, high contrast options
5. **Performance**: 60fps UI, <100ms audio latency, instant app launch

### D. Related Documents
- `CLAUDE.md` - Development guidelines and architecture
- Project README - Setup and build instructions
- API Documentation - Server integration specs

### E. Revision History
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Jan 2026 | Claude | Initial PRD with implementation details |
| 2.0 | Jan 2026 | Claude | Removed implementation details, focused on what/why |
