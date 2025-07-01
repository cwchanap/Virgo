# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for continuous integration and deployment.

## Workflows

### CI (`ci.yml`)

Runs on pushes to `main` branch and pull requests targeting `main`.

**Jobs:**
- **test**: Runs unit and UI tests on iOS Simulator and macOS
- **build-archive**: Tests archive builds for both iOS and macOS

**Matrix Strategy:**
- iOS Simulator (iPhone 16, latest OS)
- macOS (native)

**Features:**
- Latest stable Xcode version selection
- Code signing disabled for CI
- Parallel job execution
- Comprehensive test coverage

## Code Quality

SwiftLint runs automatically via **git pre-commit hooks** (not in CI) for faster feedback:

### Setup Git Hooks (One-time setup)

```bash
# Run this once after cloning the repository
./scripts/setup-git-hooks.sh
```

This script will:
- Install SwiftLint via Homebrew (if not already installed)
- Set up pre-commit hooks to run SwiftLint on staged files
- Prevent commits with linting errors

### Manual Linting

```bash
# Lint all files
swiftlint lint

# Auto-fix issues where possible
swiftlint lint --fix

# Lint specific files
swiftlint lint --path Virgo/ContentView.swift
```

## Configuration Files

- `.swiftlint.yml`: SwiftLint configuration with project-specific rules
- `ci.yml`: Main CI workflow definition
- `scripts/git-hooks/pre-commit`: Pre-commit hook for linting
- `scripts/setup-git-hooks.sh`: One-time setup script

## Requirements

- Xcode (latest stable version used in CI)
- iOS 18.5+ / macOS 14.0+
- SwiftLint (automatically installed by setup script)

## Local Testing

To run the same tests locally:

```bash
# Unit tests
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VirgoTests

# UI tests  
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:VirgoUITests

# All tests
xcodebuild test -project Virgo.xcodeproj -scheme Virgo -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Development Setup

1. Clone the repository
2. Run `./scripts/setup-git-hooks.sh` to set up code quality hooks
3. Start developing - SwiftLint will run automatically on commit!