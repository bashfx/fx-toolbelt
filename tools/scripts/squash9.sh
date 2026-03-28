#!/usr/bin/env bash
set -euo pipefail

# squash-span: squash everything in (FROM..TO] into one commit
# Usage:
#   squash9 FROM_REF TO_REF [--branch main]
#                           [--msg "Squash FROM..TO"]
#                           [--move-tags] [--delete-tags]
#                           [--no-push] [--keep-backup]
#
# Examples:
#   squash9 from-squash to-squash
#   squash9 v0.7.0 v0.9.0 --branch main --move-tags
#
# Behavior:
# - Keeps history <= FROM_REF as-is
# - Creates a single commit whose parent is FROM_REF and whose tree == TO_REF
# - Replays commits after TO_REF up to HEAD of --branch
# - Makes a local backup branch "backup/<branch>" unless --keep-backup is omitted
# - Force-pushes with lease unless --no-push

FROM_REF=${1:-}
TO_REF=${2:-}
shift 2 || true

branch="$(git rev-parse --abbrev-ref HEAD)"
msg=""
move_tags=0
delete_tags=0
do_push=1
keep_backup=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)        branch="$2"; shift 2;;
    --msg)           msg="$2"; shift 2;;
    --move-tags)     move_tags=1; shift;;
    --delete-tags)   delete_tags=1; shift;;
    --no-push)       do_push=0; shift;;
    --keep-backup)   keep_backup=1; shift;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "${FROM_REF}" || -z "${TO_REF}" ]]; then
  echo "Usage: squash-span FROM_REF TO_REF [options]" >&2
  exit 2
fi

# Resolve to exact commits
A=$(git rev-list -n1 --verify "$FROM_REF^{commit}") || { echo "FROM_REF not found: $FROM_REF"; exit 1; }
B=$(git rev-list -n1 --verify "$TO_REF^{commit}")   || { echo "TO_REF not found: $TO_REF"; exit 1; }

# Validate ancestry: A must be ancestor of B (or equal)
if ! git merge-base --is-ancestor "$A" "$B"; then
  echo "Error: $FROM_REF is not an ancestor of $TO_REF" >&2
  exit 1
fi

# Validate we’re rewriting the intended branch
git rev-parse --verify "refs/heads/$branch" >/dev/null

echo "Squashing span: ($FROM_REF..$TO_REF] on branch '$branch'"
echo "A=$A  B=$B"
read_tree="$(git rev-parse ${B}^{tree})"

# Safety backup
backup="backup/$branch"
git branch -f "$backup" "$branch" >/dev/null
echo "Created backup branch: $backup"

# Work on a rewrite branch starting at A
rewrite="rewrite/$branch-$(date +%s)"
git switch -c "$rewrite" "$A" >/dev/null

# Create the single squashed commit whose parent is A and whose tree == B^{tree}
if [[ -z "$msg" ]]; then
  msg="Squash ${FROM_REF}..${TO_REF}"
fi
new=$(printf "%s\n\n" "$msg" | git commit-tree "$read_tree" -p "$A")
git reset --hard "$new" >/dev/null
echo "Created squash commit: $(git rev-parse --short HEAD)"

# Replay everything after B up to original branch tip
orig_tip=$(git rev-parse "refs/heads/$branch")
if [[ "$orig_tip" != "$B" ]]; then
  echo "Replaying commits after $TO_REF onto squashed base…"
  git cherry-pick "$B..$orig_tip"
fi

# Swap names
git switch "$branch" >/dev/null
old="old-$branch"
git branch -M "$branch" "$old"        >/dev/null
git switch "$rewrite"                 >/dev/null
git branch -M "$branch"               >/dev/null
echo "Swapped: $old -> $branch (new history active)"

# Handle tags inside the squashed span (A..B]
# Find tags whose peeled commit is in that range
if (( move_tags || delete_tags )); then
  mapfile -t tags_in_span < <(git tag --contains "$A" | while read -r t; do
    h=$(git rev-list -n1 "$t") || continue
    if git merge-base --is-ancestor "$A" "$h" && git merge-base --is-ancestor "$h" "$B"; then
      echo "$t"
    fi
  done)

  if (( ${#tags_in_span[@]} > 0 )); then
    echo "Tags inside span: ${tags_in_span[*]}"
    if (( move_tags )); then
      for t in "${tags_in_span[@]}"; do
        git tag -f "$t" "$(git rev-parse HEAD)"
        echo "Moved tag $t -> squash commit"
      done
    fi
    if (( delete_tags )); then
      for t in "${tags_in_span[@]}"; do
        git tag -d "$t" >/dev/null
        echo "Deleted tag $t (local)"
      done
    fi
  fi
fi

# Push updates
if (( do_push )); then
  echo "Pushing rewritten '$branch' (force-with-lease)…"
  git push --force-with-lease origin "$branch"

  if (( move_tags )); then
    for t in "${tags_in_span[@]:-}"; do
      git push --force origin "refs/tags/$t"
    done
  elif (( delete_tags )); then
    for t in "${tags_in_span[@]:-}"; do
      git push origin ":refs/tags/$t"
    done
  fi
fi

# Cleanup old backup unless requested
if (( keep_backup == 0 )); then
  git branch -D "$old" >/dev/null || true
fi

echo "Done."
