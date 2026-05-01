#!/usr/bin/env bash
# seed.sh — seed the chess-knowledge database with curated docs.
# Run from the host. Requires chess-mcp-knowledge (port 5184) running.
#
# Phase 1: indexes any *.md files under docs/ if the directory exists.
# Phase 2 (TODO, see CLAUDE.md): chessprogramming.org wiki ingest via
# MediaWiki API; Stockfish + python-chess docs ingest.
set -euo pipefail

BASE="http://localhost:5184/mcp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# MCP session helpers
# ---------------------------------------------------------------------------

get_session() {
    local url="$1"
    curl -si -X POST "$url" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"seed","version":"0"}}}' \
        2>/dev/null | grep -i 'mcp-session-id' | tr -d '\r' | awk '{print $2}'
}

call_tool() {
    local url="$1"
    local session="$2"
    local id="$3"
    local name="$4"
    local args="$5"
    local max_time="${6:-300}"
    RESPONSE=$(echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"tools/call\",\"params\":{\"name\":\"$name\",\"arguments\":$args}}" \
        | curl -s -X POST "$url" \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json, text/event-stream' \
            -H "mcp-session-id: $session" \
            --data-binary @- \
            --max-time "$max_time")
    echo "$RESPONSE" | grep '^data:' | tail -1 | sed 's/^data: //' | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for c in d.get('result',{}).get('content',[]):
        if c.get('type')=='text': print(c['text'])
except: print('(parse error)')
" 2>/dev/null || echo "(no response)"
}

# ---------------------------------------------------------------------------
# Get session
# ---------------------------------------------------------------------------

echo "Connecting to chess-mcp-knowledge..."
K_SESSION=$(get_session "$BASE")
if [ -z "$K_SESSION" ]; then
    echo "ERROR: Could not get MCP session from chess-mcp-knowledge ($BASE)"
    echo "Is the container running? (Check: docker ps | grep chess-mcp-knowledge)"
    exit 1
fi
echo "  Session: $K_SESSION"

# ---------------------------------------------------------------------------
# Seed local docs (if present)
# ---------------------------------------------------------------------------

if [ -d "$REPO_DIR/docs" ]; then
    echo ""
    echo "=== Seeding mcp-chess docs ==="
    call_tool "$BASE" "$K_SESSION" 2 "seed_docs" \
        "{\"docs_path\":\"/opt/projects/mcp-chess/docs\",\"topic\":\"mcp-chess\"}"
else
    echo ""
    echo "=== Skipping mcp-chess docs (no docs/ dir) ==="
fi

# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

echo ""
echo "=== Stats ==="
call_tool "$BASE" "$K_SESSION" 9 "stats" '{}'

echo ""
echo "Done."
