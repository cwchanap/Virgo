#!/usr/bin/env bash
# Generates Virgo/Config/ServerEndpoints.env from environment variables.
#
# Used in CI so production endpoint URLs are injected at build time from GitHub
# repository variables and are never committed to the repo.
#
# Inputs (environment):
#   GRAPHQL_ENDPOINT  - GraphQL backend URL (optional; empty -> local-dev fallback)
#   R2_BASE_URL       - R2 bucket base URL for audio files (optional; empty -> audio disabled)
#
# Both are optional. The app (ServerConfig) degrades gracefully when a value is
# missing: empty GRAPHQL_ENDPOINT -> local-dev placeholder; empty R2_BASE_URL ->
# audio downloads skipped. So CI on a fork without these vars still builds green.
set -euo pipefail

OUT="Virgo/Config/ServerEndpoints.env"
mkdir -p "$(dirname "$OUT")"

GRAPHQL_ENDPOINT="${GRAPHQL_ENDPOINT:-}"
R2_BASE_URL="${R2_BASE_URL:-}"

# Write KEY=value lines (printf tolerates values containing spaces / slashes).
# Actual values are NOT echoed to the log to avoid accidental exposure.
printf 'GRAPHQL_ENDPOINT=%s\nR2_BASE_URL=%s\n' "$GRAPHQL_ENDPOINT" "$R2_BASE_URL" > "$OUT"

echo "Generated $OUT"
if [ -n "$GRAPHQL_ENDPOINT" ]; then
  echo "  GRAPHQL_ENDPOINT=<set>"
else
  echo "  GRAPHQL_ENDPOINT=<unset> -> app uses local-dev fallback"
fi
if [ -n "$R2_BASE_URL" ]; then
  echo "  R2_BASE_URL=<set>"
else
  echo "  R2_BASE_URL=<unset> -> audio downloads disabled"
fi
