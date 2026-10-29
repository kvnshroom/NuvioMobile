#!/usr/bin/env bash
# Rebase the kvn feature commits onto the latest upstream release (UPSTREAM_REPO).
#
#   kvn-prepare.sh plan     rebase, decide whether a build is needed, pick the version
#   kvn-prepare.sh rebase   rebase only; with EXPECT_TREE set, fail if the result differs
#
# Runs inside a full-history checkout of the feature branch. Writes key=value
# lines to $GITHUB_OUTPUT when it is set (plan mode).
set -euo pipefail

mode="${1:?usage: kvn-prepare.sh plan|rebase}"
upstream_repo="${UPSTREAM_REPO:?}"
fork_repo="${FORK_REPO:-${GITHUB_REPOSITORY:?}}"

git config user.name "kvn-build"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git remote add upstream "https://github.com/${upstream_repo}.git" 2>/dev/null || true
git fetch --quiet --force --tags upstream

latest="$(gh api "repos/${upstream_repo}/releases/latest" --jq .tag_name)"
# The kvn branch sits on an upstream release tag; our own tags carry ".kvn.".
base="$(git describe --tags --abbrev=0 --exclude '*.kvn.*' HEAD)"
echo "Upstream release: ${latest}, kvn base: ${base}"

# kvn commits whose feature upstream has merged since. Upstream squashes or
# rewrites PRs, so its commit never matches ours and the rebase would conflict;
# code that only exists once the feature is in proves it instead. One entry per
# feature: <exact subject of the kvn commit>|<fixed string>|<pathspec>.
UPSTREAMED_FEATURES=(
  'feat(player): add "Are you still watching?" prompt for auto-play|stillWatchingEnabled|composeApp/src/commonMain'
)

# Short hashes of kvn commits that ${latest} already contains as a feature.
upstreamed_commits() {
  local entry subject pattern pathspec
  for entry in "${UPSTREAMED_FEATURES[@]}"; do
    IFS='|' read -r subject pattern pathspec <<<"${entry}"
    git grep -q -F -e "${pattern}" "${latest}" -- "${pathspec}" 2>/dev/null || continue
    git log --format='%h%x09%s' "${base}..HEAD" | awk -F'\t' -v s="${subject}" '$2 == s { print $1 }'
  done
}

if [[ "${base}" != "${latest}" ]]; then
  mapfile -t dropped < <(upstreamed_commits)
  for sha in "${dropped[@]}"; do
    echo "Upstream ${latest} already contains $(git log -1 --format='"%s"' "${sha}"): leaving out ${sha}."
  done
  # Non-interactive rebase: the editor turns those picks into drops. git
  # appends the todo file path, which the inner bash receives as $0.
  export KVN_DROP="${dropped[*]}"
  # shellcheck disable=SC2016  # expanded by the inner bash, not here
  editor='bash -c '\''for s in $KVN_DROP; do sed -i -E "s/^pick (${s}[0-9a-f]*) /drop \1 /" "$0"; done'\'
  if ! GIT_SEQUENCE_EDITOR="${editor}" git rebase -i --onto "${latest}" "${base}"; then
    git rebase --abort || true
    echo "::error::The kvn commits no longer apply on ${latest}. Resolve the conflict on the kvn branch." >&2
    exit 1
  fi
fi

tree="$(git rev-parse 'HEAD^{tree}')"
echo "Source tree: ${tree}"

if [[ "${mode}" == "rebase" ]]; then
  if [[ -n "${EXPECT_TREE:-}" && "${EXPECT_TREE}" != "${tree}" ]]; then
    echo "::error::Source changed between jobs (${EXPECT_TREE} vs ${tree}). Re-run the workflow." >&2
    exit 1
  fi
  exit 0
fi

# Releases for this upstream version are named <upstream tag>.kvn.<n>.
prefix="${latest}.kvn."
last_n=0
last_tag=""
while read -r tag; do
  n="${tag#"${prefix}"}"
  if [[ "${tag}" == "${prefix}"* && "${n}" =~ ^[0-9]+$ ]] && ((n > last_n)); then
    last_n="${n}"
    last_tag="${tag}"
  fi
done < <(gh release list --repo "${fork_repo}" --limit 100 --json tagName --jq '.[].tagName')

build=true
if [[ -n "${last_tag}" && "${FORCE:-false}" != "true" ]]; then
  # shellcheck disable=SC2016  # the backticks are literal markdown in the release notes
  last_tree="$(gh release view "${last_tag}" --repo "${fork_repo}" --json body --jq .body |
    sed -n 's/^Source tree: `\([0-9a-f]*\)`.*/\1/p')"
  if [[ "${last_tree}" == "${tree}" ]]; then
    echo "${last_tag} already contains this source, nothing to build."
    build=false
  fi
fi

version="${prefix}$((last_n + 1))"
commits="$(git log --format='- %s' "${latest}..HEAD")"
echo "Build: ${build}, version: ${version}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "build=${build}"
    echo "version=${version}"
    echo "number=$((last_n + 1))"
    echo "upstream=${latest}"
    echo "tree=${tree}"
    echo "commits<<EOF"
    echo "${commits}"
    echo "EOF"
  } >>"${GITHUB_OUTPUT}"
fi
