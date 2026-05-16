#!/usr/bin/env bash
# Compost — worker capability smoke tests.
# Run after `ntn workers deploy` to verify each capability is wired.

set -euo pipefail

cd "$(dirname "$0")"

echo "=== ping (no notion needed) ==="
~/.local/bin/ntn workers exec ping --remote -d '{}'

echo ""
echo "=== tidyNow (needs NOTION_API_TOKEN in env push) ==="
~/.local/bin/ntn workers exec tidyNow --remote -d '{}' || echo "(expected to fail until NOTION_API_TOKEN pushed)"

echo ""
echo "=== reviewDraft (needs a real draftId) ==="
~/.local/bin/ntn workers exec reviewDraft --remote -d '{"draftId":"test","decision":"reject"}' || echo "(expected to fail without real draft)"

echo ""
echo "=== sync status ==="
~/.local/bin/ntn workers sync status --no-watch

echo ""
echo "=== latest logs ==="
~/.local/bin/ntn workers runs list --plain | head -n1 | cut -f1 | xargs -I{} ~/.local/bin/ntn workers runs logs {} 2>/dev/null | tail -20
