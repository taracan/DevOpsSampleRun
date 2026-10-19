#!/usr/bin/env bash
# apply-settings.sh: the GitHub repo settings for this project, kept as code.
#
# GitHub settings (merge buttons, branch and tag rules) live on github.com,
# not in git. This script writes them through the GitHub API, so the
# settings are reviewed in a PR like any other change and can be re-applied
# at any time. Running it twice gives the same result (idempotent).
#
# What it sets:
#   1. Merge buttons: squash merge only, the squash commit uses the PR title
#      and body, and the branch is deleted after merge.
#   2. Ruleset "main" on the default branch: changes only through a PR
#      (0 approvals: a solo owner can't approve their own PR), the required
#      checks below must pass on an up-to-date branch, linear history, no
#      force push, no deletion. No one can bypass it, admins included.
#   3. Removes the old "classic" branch protection on main, AFTER the
#      ruleset exists, so main is never unprotected. Rulesets replace it.
#   4. Release tags (v*), as two rulesets because a bypass applies to the
#      whole ruleset:
#        "release-tags-immutable": a v* tag can never be moved or deleted,
#                                  by anyone.
#        "release-tags-create":    only repository admins can create one.
#
# Usage (needs the gh CLI, signed in as a repo admin, and jq):
#   .github/settings/apply-settings.sh            apply the settings
#   DRY_RUN=1 .github/settings/apply-settings.sh  only print what it would send
#
# Read the live settings back:
#   gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge
#   gh api repos/taracan/DevOpsSampleRun/rulesets

set -euo pipefail

REPO="taracan/DevOpsSampleRun"

# Checks that must pass before a PR can merge (job names from the workflows).
# Later phases add to this list.
REQUIRED_CHECKS=(build)

GITHUB_ACTIONS_APP_ID=15368 # the checks must come from GitHub Actions
ADMIN_ROLE_ID=5             # built-in "Repository admin" role

# Sends one API call, or prints it when DRY_RUN=1. Body is read from stdin.
api() {
  local method=$1 path=$2
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    echo "--- $method $path"
    jq .
  else
    gh api --method "$method" "$path" --input - > /dev/null
    echo "ok: $method $path"
  fi
}

# Creates the ruleset, or updates it if one with the same name exists.
put_ruleset() {
  local body name id
  body=$(cat)
  name=$(jq -r .name <<< "$body")
  id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
  if [[ -n "$id" ]]; then
    api PUT "repos/$REPO/rulesets/$id" <<< "$body"
  else
    api POST "repos/$REPO/rulesets" <<< "$body"
  fi
}

# 1. Merge buttons
jq -n '{
  allow_squash_merge: true,
  allow_merge_commit: false,
  allow_rebase_merge: false,
  delete_branch_on_merge: true,
  squash_merge_commit_title: "PR_TITLE",
  squash_merge_commit_message: "PR_BODY"
}' | api PATCH "repos/$REPO"

# 2. Ruleset "main"
jq -n --argjson app "$GITHUB_ACTIONS_APP_ID" \
  --argjson checks "$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .)" '{
  name: "main",
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
  rules: [
    { type: "deletion" },
    { type: "non_fast_forward" },
    { type: "required_linear_history" },
    { type: "pull_request", parameters: {
        required_approving_review_count: 0,
        dismiss_stale_reviews_on_push: false,
        require_code_owner_review: false,
        require_last_push_approval: false,
        required_review_thread_resolution: false,
        allowed_merge_methods: ["squash"]
    } },
    { type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: true,
        required_status_checks: [ $checks[] | { context: ., integration_id: $app } ]
    } }
  ]
}' | put_ruleset

# 3. Remove the classic branch protection (only if it is still there)
if gh api "repos/$REPO/branches/main/protection" > /dev/null 2>&1; then
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    echo "--- DELETE repos/$REPO/branches/main/protection"
  else
    gh api --method DELETE "repos/$REPO/branches/main/protection"
    echo "ok: DELETE repos/$REPO/branches/main/protection"
  fi
fi

# 4. Release tags
jq -n '{
  name: "release-tags-immutable",
  target: "tag",
  enforcement: "active",
  bypass_actors: [],
  conditions: { ref_name: { include: ["refs/tags/v*"], exclude: [] } },
  rules: [ { type: "update" }, { type: "deletion" }, { type: "non_fast_forward" } ]
}' | put_ruleset

jq -n --argjson admin "$ADMIN_ROLE_ID" '{
  name: "release-tags-create",
  target: "tag",
  enforcement: "active",
  bypass_actors: [ { actor_id: $admin, actor_type: "RepositoryRole", bypass_mode: "always" } ],
  conditions: { ref_name: { include: ["refs/tags/v*"], exclude: [] } },
  rules: [ { type: "creation" } ]
}' | put_ruleset
