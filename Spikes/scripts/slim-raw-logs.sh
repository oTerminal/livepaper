#!/bin/bash
# Early captures used a wider predicate. Keep only the lines the results quote from.
cd "$(dirname "$0")/../results/raw" || exit 1
for f in *.log; do
  grep -E "app.livepaper.spike:spike|amfid\[|AMFI|pkd\[|launchd\[|deny\(|sandboxd\[|WallpaperAgent\[.*([Ll]ivepaper|not entitled)" "$f" \
    | grep -v "vfs.disk-space\|runtime-resolver\|performance_instrumentation" | cut -c1-400 > "$f.tmp"; mv "$f.tmp" "$f"
done
du -sh .
