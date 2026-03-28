# Linking A “Fresh” Repo As A Continuation Of An Older History

This playbook documents how to take a newer repository that was started fresh (no prior history) and link it as a linear continuation of an older repository’s branch, preserving continuity without a merge commit.

Applies to the workflow we used to link `../rsb` onto this repo’s `main` and fast‑forward to the newer code.

## Overview

- Goal: Make the new repo’s first commit become a child of the old repo’s tip, yielding one continuous line of history.
- Technique: `git replace --graft` to establish a temporary parent, then `git filter-branch` to materialize the link on a new branch.
- Why no conflicts: We are not merging trees; we are rewiring history. The new root’s tree remains unchanged.

## Steps

1) Add and fetch the “new” repo
   ```bash
   git remote add rsb-new ../rsb   # or a URL
   git fetch rsb-new
   # If tags would collide, fetch them namespaced:
   git fetch rsb-new +refs/tags/*:refs/tags/rsb-new/*
   ```

2) Identify linkage points
   ```bash
   OLD_TIP=$(git rev-parse main)
   NEW_ROOT=$(git rev-list --max-parents=0 rsb-new/main | tail -n 1)
   ```

3) Create a work branch from the new repo
   ```bash
   git checkout -B rsb-linked rsb-new/main
   # Optional safety copy of the unlinked chain
   git branch -f rsb-linked-unlinked rsb-new/main
   ```

4) Graft and materialize
   ```bash
   git replace --graft "$NEW_ROOT" "$OLD_TIP"
   # Rewrite only the rsb-linked branch to bake in the parent link
   GIT_SEQUENCE_EDITOR=':' git filter-branch -f -- rsb-linked
   git replace -d "$NEW_ROOT"    # remove temporary replace
   ```

5) Verify
   ```bash
   git log --graph --decorate --oneline --date-order -n 30 rsb-linked
   ```

6) Adopt the newer code on main (fast‑forward)
   ```bash
   git checkout main
   git merge --ff-only rsb-linked
   ```

## Tag Handling (Optional)

If tags from the old history should follow the linked commits, repoint them. One practical approach is to match by commit subject on `main`:

```bash
for t in $(git tag -l | sort); do
  subj=$(git rev-list -n1 --pretty=%s "$t" | sed -n '2p')
  cand=$(git log main --pretty='%h%x09%s' --grep "^$(printf %q "$subj")$" | awk -F '\t' '{print $1; exit}')
  [ -n "$cand" ] && git tag -f "$t" "$cand"
done
```

Then push with:

```bash
git push --force-with-lease origin main
git push --force-with-lease --tags
```

## Alternative: True Merge Of Unrelated Histories

Use when you want an explicit merge commit and to resolve content differences:

```bash
git checkout -B merge-test main
git merge --no-commit --no-ff --allow-unrelated-histories rsb-new/main
# Resolve conflicts (e.g., take theirs for many files):
#   git checkout --theirs <file> && git add <file>
# Commit once resolved
```

Expect “add/add” conflicts because there is no common ancestor. This is normal.

## Notes, Constraints, and Safety

- `filter-branch` runs under POSIX `sh`; avoid bash‑only syntax in filters.
- Rewriting signed commits strips signatures on rewritten commits.
- Keep safety branches (e.g., `rsb-linked-unlinked`) until you are confident.
- Use `--force-with-lease` to push; coordinate with collaborators.
- Remote renames: if the upstream changed (e.g., `rsb-framework` → `rsb.old`), update the remote URL before pushing.

## Quick Copy/Paste Template

```bash
git remote add rsb-new ../rsb
git fetch rsb-new

OLD_TIP=$(git rev-parse main)
NEW_ROOT=$(git rev-list --max-parents=0 rsb-new/main | tail -n1)

git checkout -B rsb-linked rsb-new/main
git branch -f rsb-linked-unlinked rsb-new/main

git replace --graft "$NEW_ROOT" "$OLD_TIP"
GIT_SEQUENCE_EDITOR=':' git filter-branch -f -- rsb-linked
git replace -d "$NEW_ROOT"

git checkout main
git merge --ff-only rsb-linked

# Optional: retag by subject match, then push
git push --force-with-lease origin main
git push --force-with-lease --tags
```

