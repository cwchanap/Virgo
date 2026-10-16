# Virgo

Virgo is a SwiftUI drum notation and metronome app for practicing drum patterns:
interactive drum track visualization with musical notation, a metronome, and
gameplay-style practice views synchronized to background audio.

## Platforms

- macOS 14.0+
- iPadOS (iPad-only for iOS-family builds — there is no iPhone target)

## Setup

1. Install code-quality hooks (one-time, after cloning): run
   `./scripts/setup-git-hooks.sh` to install SwiftLint and its pre-commit hook.
2. Configure server endpoints: copy `Virgo/Config/ServerEndpoints.env.example` to
   `Virgo/Config/ServerEndpoints.env` and fill in `GRAPHQL_ENDPOINT` and
   `R2_BASE_URL`. When the file is missing or a key is empty, the app falls back to
   local-dev placeholders and audio downloads are disabled — a fresh checkout still
   builds and tests green.

## Development

See [CLAUDE.md](CLAUDE.md) for exact build/test commands, CI policy, SwiftLint
limits, and architecture/contributor guidance.
