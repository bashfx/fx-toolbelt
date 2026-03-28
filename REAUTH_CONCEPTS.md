# Reauthor/Rewriter Concepts and Playbook

This document captures the core concepts, gotchas, and repeatable steps for rewriting commit identities (author/committer) across a Git repository. It is tailored to the `scripts/reauth.sh` utility that lives in this repo and the canonical copy at `repos/zindex/xbin/reauth.sh`.

## What “Reauthoring” Actually Does

- Identity fields only: Changes the Author and/or Committer name/email for matching commits. Content, messages, and timestamps remain unchanged unless Git itself adjusts them while rewriting.
- History rewrite: Any change to a commit creates a new commit SHA. Downstream SHAs change for all descendants of modified commits.
- Scope: Our script rewrites all branches and tags (`-- --all` + `--tag-name-filter cat`) so old history isn’t left reachable via tags.

## Author vs Committer

- Author: The person who originally wrote the changes.
- Committer: The person who committed them to the repository (may be a bot, CI, or different user).
- The script updates both when the source email matches, optionally gated by a source name.

## Canonical Inputs (Explicit Only)

- Source filter (required):
  - `--from-email` or `GIT_FROM_EMAIL` (required)
  - Optional `--from-name` or `GIT_FROM_NAME` to narrow by name
- Target identity (defaults):
  - `--to-name`/`--to-email`, otherwise `GIT_USER`/`GIT_EMAIL`, else `git config user.name/user.email`
- No guessing: The script never guesses the source identity; if you omit it, the script errors.

## Why Duplicates Sometimes Appear

- If only some refs are rewritten (e.g., branches but not tags), the old commits remain reachable, so you see both old and new chains.
- Our script rewrites branches and tags together to avoid this, but you must still force-push both branches and tags after reviewing locally.

## Refs 101: What Moves and What Doesn’t

- Heads: `refs/heads/*` (local branches) — rewritten and moved.
- Tags: `refs/tags/*` — rewritten and moved via `--tag-name-filter cat`.
- Remote-tracking refs: `refs/remotes/*` — not rewritten; they’re your local view of the remote. It’s normal to see “Ref 'refs/remotes/origin/main' is unchanged”.
- Backups: Saved to `refs/backup/reauth/<ID>/{heads,tags}/...` for undo.

## Safety Nets and Undo

- Backups: Every run creates a unique backup ID with copies of all heads and tags.
- Undo locally: `scripts/reauth.sh --undo <ID>` restores heads and tags to their backed-up SHAs.
- Remote safety: Nothing changes on the remote until you push. Use `--force-with-lease` to push branches and tags.

## Typical Workflow

1) Prepare
   - Ensure a clean working tree: commit or stash pending changes.
   - Choose the identities:
     - Source: `export GIT_FROM_EMAIL="old@example.com"` (and optionally `GIT_FROM_NAME`)
     - Target: `export GIT_USER="New Name"; export GIT_EMAIL="new@example.com"`

2) Dry-run preview
   - `scripts/reauth.sh --dry-run`
   - Shows: criteria, commit count, affected branches/tags, sample commits. No changes made.

3) Apply rewrite
   - `scripts/reauth.sh`
   - Creates backups, rewrites all refs locally.

4) Verify locally
   - `git show -s <tag-or-sha>` to inspect Author/Committer fields.
   - `git log --format='%h %ad %s | A:%an <%ae> | C:%cn <%ce>' --date=short | head -n 20`

5) Push
   - `git push --force-with-lease --all`
   - `git push --force-with-lease --tags`

6) Undo (if needed)
   - `scripts/reauth.sh --list-backups`
   - `scripts/reauth.sh --undo <ID>`
   - Push again with force-with-lease.

## Filter Script Constraints (Important)

- `git filter-branch` runs its filters under POSIX `sh` (not `bash`).
  - Avoid `[[ ... ]]` and other bash-only syntax.
  - Use `[ ... ]` and simple functions compatible with `sh`.
- Our env-filter updates both author and committer when the source email matches; if a source name is provided, both email AND name must match for that side.

## Force-Pushing and Team Coordination

- Rewriting history changes SHAs for you and anyone else consuming the repo.
- Coordinate with collaborators: they will need to reset/force-pull or rebase.
- Use `--force-with-lease` instead of `--force` to avoid clobbering concurrent remote updates.

## Common Messages and What They Mean

- “Ref 'refs/remotes/origin/main' is unchanged” — expected; remote-tracking refs aren’t rewritten.
- “Working tree not clean” — commit/stash changes before running.
- “Set --from-email or GIT_FROM_EMAIL/FROM_EMAIL” — the script requires an explicit source identity.
- “No commits match the criteria. Nothing to do.” — your filter did not match any commit.
- Bash/dash errors (e.g., `[[ not found]`) — happens if a filter uses bash-only syntax. The script in this repo is `sh`-compatible.

## Verifying Results

- Inspect a known tag:
  - `git show -s --format='%h %ad%nAuthor: %an <%ae>%nCommit: %cn <%ce>%n%s' --date=short <tag>`
- Ensure no old identities remain reachable:
  - `git -c pager.log=false log --all --format='%h %an <%ae> | %cn <%ce>' | grep -F 'old@example.com' || echo 'none'`
- List tags moved (after rewrite):
  - `git tag -l --format='%(refname:short) -> %(objectname:short) %(subject)'`

## Alternatives and Scaling

- `git filter-repo` (recommended by Git maintainers) is faster and safer for large repos. Our script uses `filter-branch` for portability. Consider migrating if performance becomes an issue.

## Cleanup and GC

- Backups: Keep `refs/backup/reauth/<ID>` until you are confident. You can delete old backup refs once the team has fully switched.
- Garbage collection: After removing all references to old commits and once enough time has passed, `git gc` will eventually prune unreachable objects.

## Quick Reference

- Dry-run (preview only):
  ```bash
  GIT_USER="New Name" GIT_EMAIL="new@example.com" \
  GIT_FROM_EMAIL="old@example.com" \
  scripts/reauth.sh --dry-run
  ```

- Apply rewrite:
  ```bash
  GIT_USER="New Name" GIT_EMAIL="new@example.com" \
  GIT_FROM_EMAIL="old@example.com" \
  scripts/reauth.sh
  ```

- Push changes:
  ```bash
  git push --force-with-lease --all
  git push --force-with-lease --tags
  ```

- Undo:
  ```bash
  scripts/reauth.sh --list-backups
  scripts/reauth.sh --undo <ID>
  git push --force-with-lease --all
  git push --force-with-lease --tags
  ```

