# boundaries
A=$(git rev-list -n1 v0.7.0)   # v0.7 commit
B=$(git rev-list -n1 v0.9.0)   # v0.9 commit
b=$(git rev-parse --abbrev-ref HEAD)

# safety backup
git branch backup/$b $b

# start a rewrite branch at v0.7
git switch -c rewrite $A

# make ONE commit that jumps from v0.7's tree to v0.9's tree (no merge, no conflicts)
new=$(printf "Squash v0.7.0..v0.9.0\n\n" | git commit-tree $(git rev-parse $B^{tree}) -p $A)
git reset --hard $new

# replay the original commits after v0.9
git cherry-pick $B..$b

# swap names
git switch $b
git branch -M $b old-$b
git switch rewrite
git branch -M $b

# update remote
git push --force-with-lease origin $b
