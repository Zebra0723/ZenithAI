#!/bin/bash
# Installs Zenith as a login agent. It needs bun, Claude Code logged into your plan,
# and Galaxy Link (NovaAI: galaxy/install.sh).
#   ./install.sh            install (or update) and start it
#   ./install.sh --remove   stop it; your missions stay in ~/Galaxy/Missions
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LABEL="ai.galaxy.zenith"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Zenith removed. Missions are still in ~/Galaxy/Missions."
  exit 0
fi

BUN="$(command -v bun || echo "$HOME/.bun/bin/bun")"
[ -x "$BUN" ] || { echo "Zenith needs bun: curl -fsSL https://bun.sh/install | bash" >&2; exit 1; }
CLAUDE="$(command -v claude || true)"
[ -n "$CLAUDE" ] || { echo "Zenith needs Claude Code: npm install -g @anthropic-ai/claude-code, then run claude and /login" >&2; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Galaxy/Missions"
PATHS="$(dirname "$BUN"):$(dirname "$CLAUDE"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
sed -e "s|__BUN__|$BUN|g" -e "s|__ROOT__|$ROOT|g" -e "s|__HOME__|$HOME|g" -e "s|__PATH__|$PATHS|g" \
  "$ROOT/launchd/$LABEL.plist" > "$PLIST"
# bootout returns before the job is gone, and bootstrapping into that gap fails with
# "Bootstrap failed: 5: Input/output error". Wait for it to go, and retry once.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
for _ in $(seq 20); do launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null || { sleep 2; launchctl bootstrap "$DOMAIN" "$PLIST"; }
echo "Zenith is running. It takes missions from the other members; they land in ~/Galaxy/Missions."
