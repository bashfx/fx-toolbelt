#!/bin/bash

# Dependency analysis script for rust projects
# Finds all Cargo.toml files and analyzes dependency versions

echo "🔍 Analyzing dependencies across rust projects..."
echo

# Find all Cargo.toml files and process them
find /home/xnull/repos/code/rust -name "Cargo.toml" -type f | while read -r cargo_file; do
    project_path=$(dirname "$cargo_file")
    project_name=$(basename "$project_path")

    # Skip if this is a nested Cargo.toml (like in target/ directories)
    if [[ "$cargo_file" =~ /target/ ]]; then
        continue
    fi

    echo "📦 $project_name ($project_path)"

    # Extract dependencies section (stop at next section or EOF)
    awk '/^\[dependencies\]/{flag=1; next} /^\[/{flag=0} flag && /^[a-zA-Z]/ {print "  " $0}' "$cargo_file"

    # Extract dev-dependencies if they exist
    if grep -q "^\[dev-dependencies\]" "$cargo_file"; then
        echo "  [dev-dependencies]"
        awk '/^\[dev-dependencies\]/{flag=1; next} /^\[/{flag=0} flag && /^[a-zA-Z]/ {print "    " $0}' "$cargo_file"
    fi

    echo
done

echo
echo "📊 Dependency version analysis..."
echo

# Create temporary file for dependency collection
temp_file=$(mktemp)

# Collect all dependencies with project info
find /home/xnull/repos/code/rust -name "Cargo.toml" -type f | while read -r cargo_file; do
    if [[ "$cargo_file" =~ /target/ ]]; then
        continue
    fi

    project_path=$(dirname "$cargo_file")
    project_name=$(basename "$project_path")

    # Extract dependencies and format as: dep_name|version|project_name
    awk -v proj="$project_name" '
    /^\[dependencies\]/{in_deps=1; next}
    /^\[dev-dependencies\]/{in_deps=0; in_dev=1; next}
    /^\[/{in_deps=0; in_dev=0}
    (in_deps || in_dev) && /^[a-zA-Z]/ {
        # Handle different dependency formats
        if (match($0, /^([a-zA-Z0-9_-]+)\s*=\s*"([^"]+)"/, arr)) {
            print arr[1] "|" arr[2] "|" proj
        } else if (match($0, /^([a-zA-Z0-9_-]+)\s*=\s*\{\s*version\s*=\s*"([^"]+)"/, arr)) {
            print arr[1] "|" arr[2] "|" proj
        } else if (match($0, /^([a-zA-Z0-9_-]+)\s*=\s*\{\s*path/, arr)) {
            print arr[1] "|path|" proj
        }
    }' "$cargo_file"
done > "$temp_file"

# Sort and group by dependency name
sort "$temp_file" | awk -F'|' '
{
    dep = $1
    version = $2
    project = $3

    if (dep != last_dep && last_dep != "") {
        print ""
    }

    if (dep != last_dep) {
        printf "🔧 %s:\n", dep
        last_dep = dep
    }

    printf "  %-15s -> %s\n", project, version
}'

# Clean up
rm "$temp_file"

echo
echo "✅ Analysis complete!"