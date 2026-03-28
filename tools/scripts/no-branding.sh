#!/bin/bash

# no-branding.sh - Remove Claude branding from git commit history
# Usage: ./no-branding.sh [--start-commit COMMIT_HASH] [--dry-run] [--help]

set -euo pipefail

# Default values
START_COMMIT=""
DRY_RUN=false
FORCE=false
LIST_ONLY=false
CLEAN_ALL=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
no-branding.sh - Remove Claude branding from git commit history

USAGE:
    ./no-branding.sh [OPTIONS]

OPTIONS:
    --start-commit HASH    Start cleaning from this commit hash (exclusive)
                          If not provided, will scan all commits and suggest a range
    --list                List all commits with Claude branding (read-only)
    --all                 Clean all commits with Claude branding automatically
    --dry-run             Show what would be changed without making changes
    --force               Skip safety checks and confirmations
    --help                Show this help message

EXAMPLES:
    # List all commits with Claude branding
    ./no-branding.sh --list

    # Clean all branded commits automatically
    ./no-branding.sh --all

    # Scan repository and get recommendations
    ./no-branding.sh --dry-run

    # Clean from a specific commit to HEAD
    ./no-branding.sh --start-commit abc123def

    # Clean all Claude branding with confirmation
    ./no-branding.sh --force

SAFETY:
    This script rewrites git history. Make sure you:
    1. Have backups of your repository
    2. Coordinate with team members before running on shared repositories
    3. Force-push changes to remote repositories if needed

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --start-commit)
            START_COMMIT="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --all)
            CLEAN_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository"
    exit 1
fi

# Check for uncommitted changes (skip for read-only modes)
if [[ "$LIST_ONLY" != "true" && "$DRY_RUN" != "true" ]] && ! git diff-index --quiet HEAD -- 2>/dev/null; then
    print_error "Repository has uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Function to find commits with Claude branding
find_branded_commits() {
    print_status "Scanning for commits with Claude branding..."
    
    # Search for commits containing Claude branding
    local branded_commits
    branded_commits=$(git log --grep="Generated with.*Claude\|Co-Authored-By.*Claude" --format="%H %s" 2>/dev/null || true)
    
    if [[ -z "$branded_commits" ]]; then
        print_success "No commits with Claude branding found!"
        exit 0
    fi
    
    echo
    print_warning "Found commits with Claude branding:"
    echo "$branded_commits" | head -10
    
    local total_count
    total_count=$(echo "$branded_commits" | wc -l)
    
    if [[ $total_count -gt 10 ]]; then
        print_warning "... and $((total_count - 10)) more commits"
    fi
    
    echo
    print_status "Total commits with branding: $total_count"
    
    # Get the oldest and newest branded commits
    local oldest_commit newest_commit
    oldest_commit=$(echo "$branded_commits" | tail -1 | cut -d' ' -f1)
    newest_commit=$(echo "$branded_commits" | head -1 | cut -d' ' -f1)
    
    echo
    print_status "Recommended start commit (oldest branded commit's parent):"
    git log --oneline -1 "${oldest_commit}^" 2>/dev/null || echo "  (no parent found - would clean entire history)"
    
    echo
    print_status "Range that would be cleaned: ${oldest_commit}^..HEAD"
    
    return 0
}

# Function to list all commits with Claude branding
list_branded_commits() {
    print_status "Listing all commits with Claude branding..."
    
    # Search for commits containing Claude branding (current branch only)
    local branded_commits
    branded_commits=$(git log --grep="Generated with.*Claude\|Co-Authored-By.*Claude" --format="%H %ad %s" --date=short 2>/dev/null || true)
    
    if [[ -z "$branded_commits" ]]; then
        print_success "No commits with Claude branding found!"
        return 0
    fi
    
    echo
    print_warning "Commits with Claude branding:"
    echo "----------------------------------------"
    printf "%-12s %-12s %s\n" "COMMIT" "DATE" "SUBJECT"
    echo "----------------------------------------"
    
    while IFS=' ' read -r commit_hash commit_date rest_of_line; do
        # Truncate commit hash to 8 characters for display
        local short_hash="${commit_hash:0:8}"
        # Truncate subject line if too long
        local subject="$rest_of_line"
        if [[ ${#subject} -gt 60 ]]; then
            subject="${subject:0:57}..."
        fi
        printf "%-12s %-12s %s\n" "$short_hash" "$commit_date" "$subject"
    done <<< "$branded_commits"
    
    echo "----------------------------------------"
    
    local total_count
    total_count=$(echo "$branded_commits" | wc -l)
    print_status "Total commits with Claude branding: $total_count"
    
    # Show branch information
    echo
    print_status "Branch analysis:"
    while IFS=' ' read -r commit_hash _; do
        local branches
        branches=$(git branch --contains "$commit_hash" 2>/dev/null | sed 's/^[ *]*//' | tr '\n' ' ' | sed 's/ $//')
        if [[ -n "$branches" ]]; then
            printf "  %s: %s\n" "${commit_hash:0:8}" "$branches"
        fi
    done <<< "$branded_commits"
    
    # Get the oldest and newest branded commits for recommendations
    local oldest_commit newest_commit
    oldest_commit=$(echo "$branded_commits" | tail -1 | cut -d' ' -f1)
    newest_commit=$(echo "$branded_commits" | head -1 | cut -d' ' -f1)
    
    echo
    print_status "Cleaning recommendations:"
    print_status "  Oldest branded commit: ${oldest_commit:0:8}"
    print_status "  Newest branded commit: ${newest_commit:0:8}"
    print_status "  Suggested start commit: $(git log --oneline -1 "${oldest_commit}^" 2>/dev/null | cut -d' ' -f1 || echo "N/A")"
    print_status "  Command: ./no-branding.sh --start-commit ${oldest_commit}^"
    
    return 0
}

# Function to automatically clean all commits with Claude branding
clean_all_branded_commits() {
    print_status "Auto-cleaning all commits with Claude branding..."
    
    # Get all commits with Claude branding, sorted from oldest to newest
    local branded_commits
    branded_commits=$(git log --grep="Generated with.*Claude\|Co-Authored-By.*Claude" --format="%H" --reverse 2>/dev/null || true)
    
    if [[ -z "$branded_commits" ]]; then
        print_success "No commits with Claude branding found!"
        return 0
    fi
    
    local total_commits
    total_commits=$(echo "$branded_commits" | wc -l)
    
    echo
    print_warning "Found $total_commits commits with Claude branding to clean"
    
    # Show what we're about to clean
    echo
    print_status "Commits to be cleaned:"
    local counter=1
    while IFS= read -r commit_hash; do
        local commit_subject
        commit_subject=$(git log --format="%s" -1 "$commit_hash" 2>/dev/null)
        printf "  %2d. %s %s\n" "$counter" "${commit_hash:0:8}" "$commit_subject"
        ((counter++))
    done <<< "$branded_commits"
    
    # Safety confirmation unless forced
    if [[ "$FORCE" != "true" ]]; then
        echo
        print_warning "This will rewrite git history for $total_commits commits"
        print_warning "This action cannot be easily undone!"
        echo
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            print_status "Operation cancelled"
            return 0
        fi
    fi
    
    echo
    print_status "Starting automatic cleanup of all branded commits..."
    
    # Get the oldest branded commit's parent as the starting point
    local oldest_commit
    oldest_commit=$(echo "$branded_commits" | head -1)
    local start_commit="${oldest_commit}^"
    
    # Validate that the parent commit exists
    if ! git rev-parse --verify "$start_commit" >/dev/null 2>&1; then
        print_warning "Oldest branded commit has no parent - cleaning entire history"
        start_commit=$(git rev-list --max-parents=0 HEAD)
    fi
    
    print_status "Cleaning from commit: $start_commit"
    
    # Set the squelch warning to avoid filter-branch warnings
    export FILTER_BRANCH_SQUELCH_WARNING=1
    
    # Create the filter script
    local filter_script='sed "/^🤖 Generated with.*Claude/d; /^Co-Authored-By: Claude/d"'
    
    print_status "Running git filter-branch on range ${start_commit}..HEAD"
    
    if git filter-branch -f --msg-filter "$filter_script" -- "${start_commit}..HEAD" 2>/dev/null; then
        print_success "Successfully cleaned all commit messages!"
        
        # Clean up backup references
        print_status "Cleaning up backup references..."
        rm -rf .git/refs/original/ 2>/dev/null || true
        
        print_success "Auto-cleanup complete!"
        
        # Verify results
        echo
        print_status "Verification: Checking for remaining Claude branding..."
        local remaining_branded
        remaining_branded=$(git log --grep="Generated with.*Claude\|Co-Authored-By.*Claude" --format="%H" --all 2>/dev/null || true)
        
        if [[ -z "$remaining_branded" ]]; then
            print_success "✓ No Claude branding found - cleanup was successful!"
        else
            local remaining_count
            remaining_count=$(echo "$remaining_branded" | wc -l)
            print_warning "⚠ $remaining_count commits still have Claude branding (possibly outside the cleaned range)"
        fi
        
        echo
        print_warning "IMPORTANT: Git history has been rewritten!"
        print_warning "If you have already pushed these commits, you will need to force-push:"
        print_warning "  git push --force-with-lease origin <branch-name>"
        
    else
        print_error "Failed to clean commits"
        return 1
    fi
}

# Function to show what would be changed in dry-run mode
show_dry_run() {
    local start_ref="$1"
    
    print_status "DRY RUN: Showing commits that would be modified..."
    echo
    
    # Get commits in range that have branding
    local commits_to_clean
    commits_to_clean=$(git log --grep="Generated with.*Claude\|Co-Authored-By.*Claude" --format="%H" "${start_ref}..HEAD" 2>/dev/null || true)
    
    if [[ -z "$commits_to_clean" ]]; then
        print_success "No commits with Claude branding found in range ${start_ref}..HEAD"
        return 0
    fi
    
    while IFS= read -r commit_hash; do
        echo "----------------------------------------"
        print_warning "Commit: $commit_hash"
        echo
        echo "Current message:"
        git show --format="%B" --no-patch "$commit_hash" | sed 's/^/  /'
        echo
        echo "Would become:"
        git show --format="%B" --no-patch "$commit_hash" | \
            sed '/^🤖 Generated with.*Claude/d; /^Co-Authored-By: Claude/d' | \
            sed 's/^/  /'
        echo
    done <<< "$commits_to_clean"
    
    local count
    count=$(echo "$commits_to_clean" | wc -l)
    print_status "Total commits that would be modified: $count"
}

# Function to perform the actual cleaning
clean_commits() {
    local start_ref="$1"
    
    print_status "Cleaning Claude branding from commits in range: ${start_ref}..HEAD"
    
    # Set the squelch warning to avoid filter-branch warnings
    export FILTER_BRANCH_SQUELCH_WARNING=1
    
    # Create the filter script
    local filter_script='sed "/^🤖 Generated with.*Claude/d; /^Co-Authored-By: Claude/d"'
    
    print_status "Running git filter-branch..."
    
    if git filter-branch -f --msg-filter "$filter_script" -- "${start_ref}..HEAD"; then
        print_success "Successfully cleaned commit messages!"
        
        # Clean up backup references
        print_status "Cleaning up backup references..."
        rm -rf .git/refs/original/ 2>/dev/null || true
        
        print_success "Cleanup complete!"
        
        echo
        print_warning "IMPORTANT: Git history has been rewritten!"
        print_warning "If you have already pushed these commits, you will need to force-push:"
        print_warning "  git push --force-with-lease origin <branch-name>"
        
    else
        print_error "Failed to clean commits"
        return 1
    fi
}

# Main logic
main() {
    print_status "Claude Branding Removal Tool"
    echo "Repository: $(git rev-parse --show-toplevel)"
    echo "Current branch: $(git branch --show-current)"
    echo

    # Handle list-only mode
    if [[ "$LIST_ONLY" == "true" ]]; then
        list_branded_commits
        exit 0
    fi

    # Handle clean-all mode
    if [[ "$CLEAN_ALL" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "DRY RUN: Would clean all commits with Claude branding"
            list_branded_commits
        else
            clean_all_branded_commits
        fi
        exit 0
    fi

    # If no start commit provided, scan and show recommendations
    if [[ -z "$START_COMMIT" ]]; then
        find_branded_commits
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo
            print_status "Use --start-commit with the recommended commit hash to proceed"
            exit 0
        fi
        
        if [[ "$FORCE" != "true" ]]; then
            echo
            print_warning "No start commit specified. Run with --dry-run to see recommendations."
            print_warning "Or specify --start-commit HASH to clean from a specific point."
            exit 1
        fi
        
        # If force is enabled, use the oldest branded commit's parent
        local oldest_branded
        oldest_branded=$(git log --grep="Generated with.*Claude\|Co-Authored-By.*Claude" --format="%H" --all | tail -1)
        
        if [[ -n "$oldest_branded" ]]; then
            START_COMMIT="${oldest_branded}^"
            print_status "Force mode: Using start commit: $START_COMMIT"
        else
            print_success "No Claude branding found!"
            exit 0
        fi
    fi

    # Validate start commit
    if ! git rev-parse --verify "$START_COMMIT" >/dev/null 2>&1; then
        print_error "Invalid start commit: $START_COMMIT"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        show_dry_run "$START_COMMIT"
        exit 0
    fi

    # Safety confirmation unless forced
    if [[ "$FORCE" != "true" ]]; then
        echo
        print_warning "This will rewrite git history from $START_COMMIT to HEAD"
        print_warning "This action cannot be easily undone!"
        echo
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            print_status "Operation cancelled"
            exit 0
        fi
    fi

    # Perform the cleaning
    clean_commits "$START_COMMIT"
}

# Run main function
main "$@"