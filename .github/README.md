# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for continuous integration and deployment.

## Workflows

### CI (`ci.yml`)

Runs on every push and pull request to `main` and `dev` branches.

**Jobs:**
- **test**: Runs unit and UI tests on iOS Simulator and macOS
- **lint**: Runs SwiftLint to ensure code quality
- **build-archive**: Tests archive builds for both iOS and macOS

**Matrix Strategy:**
- iOS Simulator (iPhone 16, latest OS)
- macOS (native)

**Features:**
- Automatic Xcode version selection
- Code signing disabled for CI
- Parallel job execution
- Comprehensive test coverage

## Configuration Files

- `.swiftlint.yml`: SwiftLint configuration with project-specific rules
- `ci.yml`: Main CI workflow definition

## Requirements

- Xcode 16.4+
- iOS 18.5+ / macOS 14.0+
- SwiftLint (automatically installed in CI)

## Local Testing

To run the same tests locally:

```bash
# Unit tests
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VirgoTests

# UI tests  
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VirgoUITests

# SwiftLint
swiftlint lint
```