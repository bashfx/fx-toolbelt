#!/usr/bin/env bash
set -euo pipefail

# reauth.sh — rewrite author/committer identities across the repo with backups and undo
#
# Features
# - Backs up all heads and tags to refs/backup/reauth/<ID>/...
# - Rewrites ALL refs (branches and tags) so no old commits remain reachable
# - Changes both Author and Committer identity when matching the provided criteria
# - Provides --undo <ID> to restore all heads/tags from a backup
# - Offers --dry-run and --list-backups helpers
# - Defaults new identity to GIT_USER/GIT_EMAIL (or git config) if flags omitted
# - If --from-email is omitted, uses GIT_FROM_EMAIL/FROM_EMAIL (no guessing)
#
# Usage examples
#   scripts/reauth.sh \
#     --from-email "old@example.com" \
#     --to-name "New Name" --to-email "new@example.com"
#
#   scripts/reauth.sh --undo 20250914T203500Z
#   scripts/reauth.sh --list-backups
#
# Notes
# - This uses `git filter-branch` with `--env-filter` and `--tag-name-filter cat` over `--all`.
#   This rewrites all branches and tags so the old history is not left referenced by tags.
# - After a successful run, you must force-push branches and tags:
#     git push --force-with-lease --all
#     git push --force-with-lease --tags
# - Undo does not delete rewritten objects; it simply restores the refs to their backups.
# - For large repos, consider installing `git filter-repo` and migrating this script accordingly.

usage() {
  cat <<EOF
Rewrite author/committer identities across all refs with backups and undo.

Required (change criteria and new identity):
  --from-email EMAIL         Only rewrite commits where AUTHOR or COMMITTER email matches
  --to-name NAME             New name to set on matching commits (defaults to $GIT_USER or git config user.name)
  --to-email EMAIL           New email to set on matching commits (defaults to $GIT_EMAIL or git config user.email)

Optional:
  --from-name NAME           Additionally require matching name (default: any name)
  --dry-run                  Print planned actions and affected refs/commits; no changes
  --yes                      Skip interactive confirmation prompts
  --undo ID                  Restore all heads/tags from backup ID
  --list-backups             List available backup IDs

Environment defaults for identities:
  GIT_FROM_EMAIL, FROM_EMAIL Use as source email if --from-email is omitted (required; no guessing)
  GIT_FROM_NAME,  FROM_NAME  Optional source name filter if --from-name is omitted
  GIT_USER, GIT_EMAIL        Used when --to-name/--to-email are not provided
  GIT_AUTHOR_NAME/EMAIL      Secondary fallback if set; then git config user.name/email

Examples:
  scripts/reauth.sh --from-email old@example.com \
    --to-name "New Name" --to-email new@example.com

  scripts/reauth.sh --undo 20250914T203500Z
  scripts/reauth.sh --list-backups
EOF
}

die() { echo "Error: $*" >&2; exit 1; }
info() { echo "[reauth] $*" >&2; }

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[[ -n "$repo_root" ]] || die "Not a git repository."
cd "$repo_root"

action="rewrite"
dry_run=false
auto_yes=false
from_email=""
from_name=""
to_name=""
to_email=""
undo_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-email) from_email=${2:-}; shift 2;;
    --from-name)  from_name=${2:-};  shift 2;;
    --to-name)    to_name=${2:-};    shift 2;;
    --to-email)   to_email=${2:-};   shift 2;;
    --dry-run)    dry_run=true;      shift;;
    --yes|-y)     auto_yes=true;     shift;;
    --undo)       action="undo"; undo_id=${2:-}; shift 2;;
    --list-backups) action="list";  shift;;
    -h|--help)    usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

timestamp_utc() {
  # Portable UTC timestamp: YYYYMMDDTHHMMSSZ
  date -u +%Y%m%dT%H%M%SZ
}

ensure_clean() {
  if ! git diff --quiet || ! git diff --staged --quiet; then
    die "Working tree not clean. Commit or stash changes first."
  fi
}

list_backups() {
  info "Available backups under refs/backup/reauth/:"
  git for-each-ref --format='%(refname)' 'refs/backup/reauth/*' \
    | sed -E 's#^refs/backup/reauth/([^/]+)/.*#\1#' \
    | sort -u
}

do_undo() {
  local id="$1"
  [[ -n "$id" ]] || die "--undo requires an ID (see --list-backups)."

  # Verify backup exists
  if ! git show-ref --verify --quiet "refs/backup/reauth/$id" 2>/dev/null; then
    # The umbrella ref might not exist; check at least one child ref.
    local count
    count=$(git for-each-ref --format='%(refname)' "refs/backup/reauth/$id/*" | wc -l | tr -d ' ')
    [[ "$count" != "0" ]] || die "No backup found for ID $id"
  fi

  ensure_clean

  info "Restoring heads and tags from backup $id ..."
  # Restore heads
  while IFS= read -r line; do
    local_ref=${line% *}
    sha=${line#* }
    target_ref="refs/heads/${local_ref#refs/backup/reauth/$id/heads/}"
    info "  head: $target_ref <- $sha"
    git update-ref -m "reauth: undo $id" "$target_ref" "$sha"
  done < <(git for-each-ref --format='%(refname) %(objectname)' "refs/backup/reauth/$id/heads/*")

  # Restore tags
  while IFS= read -r line; do
    local_ref=${line% *}
    sha=${line#* }
    target_ref="refs/tags/${local_ref#refs/backup/reauth/$id/tags/}"
    info "  tag:  $target_ref <- $sha"
    git update-ref -m "reauth: undo $id" "$target_ref" "$sha"
  done < <(git for-each-ref --format='%(refname) %(objectname)' "refs/backup/reauth/$id/tags/*")

  info "Undo complete. Review and push with --force-with-lease if desired."
}

backup_refs() {
  local id="$1"
  info "Creating backup: refs/backup/reauth/$id"

  local n_heads=0 n_tags=0
  # Backup heads
  while IFS= read -r line; do
    ref=${line% *}
    sha=${line#* }
    bkp="refs/backup/reauth/$id/heads/${ref#refs/heads/}"
    git update-ref -m "reauth: backup $id" "$bkp" "$sha"
    n_heads=$((n_heads+1))
  done < <(git for-each-ref --format='%(refname) %(objectname)' refs/heads)

  # Backup tags
  while IFS= read -r line; do
    ref=${line% *}
    sha=${line#* }
    bkp="refs/backup/reauth/$id/tags/${ref#refs/tags/}"
    git update-ref -m "reauth: backup $id" "$bkp" "$sha"
    n_tags=$((n_tags+1))
  done < <(git for-each-ref --format='%(refname) %(objectname)' refs/tags)

  info "Backed up $n_heads heads and $n_tags tags."
}

confirm() {
  $auto_yes && return 0
  read -r -p "$1 [y/N] " ans || true
  case "${ans,,}" in
    y|yes) return 0;;
    *) return 1;;
  esac
}

do_rewrite() {
  # Resolve destination identity from flags or environment defaults.
  # Priority: flags > GIT_USER/GIT_EMAIL > GIT_AUTHOR_NAME/EMAIL > git config
  if [[ -z "${to_name}" ]]; then
    if [[ -n "${GIT_USER:-}" ]]; then
      to_name="$GIT_USER"
    elif [[ -n "${GIT_AUTHOR_NAME:-}" ]]; then
      to_name="$GIT_AUTHOR_NAME"
    else
      to_name="$(git config --get user.name 2>/dev/null || true)"
    fi
  fi
  if [[ -z "${to_email}" ]]; then
    if [[ -n "${GIT_EMAIL:-}" ]]; then
      to_email="$GIT_EMAIL"
    elif [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
      to_email="$GIT_AUTHOR_EMAIL"
    elif [[ -n "${GIT_COMMITTER_EMAIL:-}" ]]; then
      to_email="$GIT_COMMITTER_EMAIL"
    else
      to_email="$(git config --get user.email 2>/dev/null || true)"
    fi
  fi

  [[ -n "$to_name" && -n "$to_email" ]] || die "Provide --to-name/--to-email or set GIT_USER/GIT_EMAIL (or configure user.name/user.email)"

  # Resolve source matcher from flags or env (no guessing)
  if [[ -z "$from_email" ]]; then
    if [[ -n "${GIT_FROM_EMAIL:-}" ]]; then
      from_email="$GIT_FROM_EMAIL"
    elif [[ -n "${FROM_EMAIL:-}" ]]; then
      from_email="$FROM_EMAIL"
    else
      die "Set --from-email or GIT_FROM_EMAIL/FROM_EMAIL"
    fi
  fi

  # Optionally resolve from_name from env if not given
  if [[ -z "$from_name" ]]; then
    if [[ -n "${GIT_FROM_NAME:-}" ]]; then
      from_name="$GIT_FROM_NAME"
    elif [[ -n "${FROM_NAME:-}" ]]; then
      from_name="$FROM_NAME"
    fi
  fi

  ensure_clean

  local id
  id=$(timestamp_utc)

  info "Planned rewrite:";
  info "  Match email: $from_email";
  [[ -n "$from_name" ]] && info "  Match name:  $from_name" || true
  info "  Set to:     $to_name <$to_email>"
  info "  Scope:      all branches and tags (--all + --tag-name-filter cat)"

  if $dry_run; then
    # Show what would be affected
    info "Analyzing repository for matching commits..."
    tmp_shas=$(mktemp -t reauth-shas.XXXXXX)
    trap 'rm -f "$tmp_shas"' EXIT
    git -c pager.log=false log --all --format='%H%x09%an%x09%ae%x09%cn%x09%ce' \
      | awk -v fe="$from_email" -v fn="$from_name" '
          BEGIN { FS="\t" }
          {
            sha=$1; an=$2; ae=$3; cn=$4; ce=$5;
            m=(ae==fe || ce==fe);
            if (fn!="") m=(m && (an==fn || cn==fn));
            if (m) print sha;
          }
        ' \
      | sort -u > "$tmp_shas"

    n_commits=$(wc -l < "$tmp_shas" | tr -d ' ')
    if [[ "$n_commits" = "0" ]]; then
      info "No commits match the criteria. Nothing to do."
      return 0
    fi

    info "Matched commits: $n_commits"

    # Determine branches and tags that contain at least one matched commit
    tmp_br=$(mktemp -t reauth-br.XXXXXX); tmp_tag=$(mktemp -t reauth-tag.XXXXXX)
    trap 'rm -f "$tmp_shas" "$tmp_br" "$tmp_tag"' EXIT

    # Limit how many SHAs we query for ref containment (for speed)
    limit=200
    c=0
    while IFS= read -r sha; do
      git for-each-ref --format='%(refname:short)' --contains "$sha" refs/heads >> "$tmp_br" || true
      git for-each-ref --format='%(refname:short)' --contains "$sha" refs/tags  >> "$tmp_tag" || true
      c=$((c+1)); [[ $c -ge $limit ]] && break || true
    done < "$tmp_shas"

    sort -u "$tmp_br" -o "$tmp_br" || true
    sort -u "$tmp_tag" -o "$tmp_tag" || true

    n_br=$(wc -l < "$tmp_br" | tr -d ' ')
    n_tag=$(wc -l < "$tmp_tag" | tr -d ' ')

    info "Branches containing affected commits: $n_br"
    head -n 12 "$tmp_br" | sed 's/^/  - /'
    [[ "$n_br" -gt 12 ]] && echo "  ... and $((n_br-12)) more" >&2 || true

    info "Tags containing affected commits: $n_tag"
    head -n 12 "$tmp_tag" | sed 's/^/  - /'
    [[ "$n_tag" -gt 12 ]] && echo "  ... and $((n_tag-12)) more" >&2 || true

    info "Sample affected commits:"
    head -n 10 "$tmp_shas" | xargs -r -n1 git show -s --date=short --format='  - %h %ad %s | A:%an <%ae> | C:%cn <%ce>'

    info "Dry-run complete. No changes made."
    return 0
  fi

  backup_refs "$id"

  info "Running filter-branch (this may take a while)..."

  # Build the env-filter script. It runs under 'sh', not bash.
  # We match and change author/committer independently based on from_email (+ optional from_name).
  env_filter=''
  env_filter+='from_email='"'${from_email}'"'; '
  env_filter+='from_name='"'${from_name}'"'; '
  env_filter+='to_name='"'${to_name}'"'; '
  env_filter+='to_email='"'${to_email}'"'; '
  env_filter+='match_name() { [ -z "$from_name" ] || [ "$1" = "$from_name" ]; }; '
  env_filter+='echo "$GIT_COMMIT $GIT_AUTHOR_EMAIL $GIT_COMMITTER_EMAIL" >> .git/reauth.debug; '
  env_filter+='if [ "$GIT_AUTHOR_EMAIL" = "$from_email" ] && match_name "$GIT_AUTHOR_NAME"; then '
    env_filter+='  echo "A $GIT_COMMIT" >> .git/reauth.debug; '
    env_filter+='  GIT_AUTHOR_NAME="$to_name"; GIT_AUTHOR_EMAIL="$to_email"; '
  env_filter+='fi; '
  env_filter+='if [ "$GIT_COMMITTER_EMAIL" = "$from_email" ] && match_name "$GIT_COMMITTER_NAME"; then '
    env_filter+='  echo "C $GIT_COMMIT" >> .git/reauth.debug; '
    env_filter+='  GIT_COMMITTER_NAME="$to_name"; GIT_COMMITTER_EMAIL="$to_email"; '
  env_filter+='fi; '
  env_filter+='export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL'

  # shellcheck disable=SC2086
  git filter-branch -f \
    --env-filter "$env_filter" \
    --tag-name-filter cat \
    -- --all >/dev/null

  info "Rewrite complete. Backup ID: $id"
  info "Next: review 'git log --decorate --graph', then push:"
  info "  git push --force-with-lease --all"
  info "  git push --force-with-lease --tags"
}

case "$action" in
  list)
    list_backups
    ;;
  undo)
    do_undo "$undo_id"
    ;;
  rewrite)
    do_rewrite
    ;;
  *) die "unknown action: $action";;
esac
