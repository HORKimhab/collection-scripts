WORKSPACE="your_workspace_id"

mkdir bitbucket-repos
cd bitbucket-repos || exit

curl -s "https://api.bitbucket.org/2.0/repositories/$WORKSPACE?pagelen=100" \
| jq -r '.values[].links.clone[] | select(.name=="https") | .href' \
| while read repo; do
  git clone "$repo"
done
