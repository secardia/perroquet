#!/bin/sh
# Usage: dl.sh <repo> <dest> [grep -E exclude regex]. Resumes partial files, skips complete ones.
set -e
REPO=$1; DEST=$2; EXCL=${3:-^$}
LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
curl -sfL "https://huggingface.co/api/models/$REPO/tree/main?recursive=true" \
  | python3 -c "import json,sys;[print(f['size'], f['path']) for f in json.load(sys.stdin) if f['type']=='file']" \
  | { grep -Ev "$EXCL" || true; } > "$LIST"
[ -s "$LIST" ] || { echo "$REPO: no files to download" >&2; exit 1; }
failed=0
while read -r size f; do
  mkdir -p "$DEST/$(dirname "$f")"
  have=$(stat -f %z "$DEST/$f" 2>/dev/null || echo 0)
  [ "$have" = "$size" ] || curl -sfL --retry 5 -C - -o "$DEST/$f" "https://huggingface.co/$REPO/resolve/main/$f" || { echo "FAILED $REPO/$f" >&2; failed=1; }
done < "$LIST"
echo "$REPO: $(du -sh "$DEST" | cut -f1)"
exit $failed
