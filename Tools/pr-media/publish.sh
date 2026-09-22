#!/bin/zsh
# usage: publish.sh <pr number> <file>…
# Puts the files on the pr-media branch under pr-<number>/ and prints the Markdown that embeds
# them: images and GIFs inline, videos as links to GitHub's player. The branch is an orphan, so
# master's history stays free of media.
set -e
pr=$1; shift
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
git -C "$root" fetch -q origin pr-media 2>/dev/null || true
if git -C "$root" show-ref -q refs/remotes/origin/pr-media; then
  git -C "$root" worktree add -q "$tmp" origin/pr-media --detach
  git -C "$tmp" checkout -q -B pr-media
else
  git -C "$root" worktree add -q --detach "$tmp"
  git -C "$tmp" checkout -q --orphan pr-media
  git -C "$tmp" rm -rfq .
  printf '# PR media\n\nScreenshots and recordings referenced from pull requests, one folder per PR.\n' > "$tmp/README.md"
fi
mkdir -p "$tmp/pr-$pr"
cp "$@" "$tmp/pr-$pr/"
git -C "$tmp" add -A
git -C "$tmp" commit -q -m "PR #$pr media" || true
git -C "$tmp" push -q origin pr-media
git -C "$root" worktree remove --force "$tmp"
for f in "$@"; do
  b=$(basename "$f")
  case $b in
    *.mp4|*.mov) echo "[$b](https://github.com/$repo/blob/pr-media/pr-$pr/$b)";;
    *) echo "![$b](https://raw.githubusercontent.com/$repo/pr-media/pr-$pr/$b)";;
  esac
done
