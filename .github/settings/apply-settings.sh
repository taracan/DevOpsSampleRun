#!/usr/bin/env bash
# apply-settings.sh: the GitHub repo settings for this project, kept as code.
#
# GitHub settings (merge buttons, branch and tag rules) live on github.com,
# not in git. This script writes them through the GitHub API, so the
# settings are reviewed in a PR like any other change and can be re-applied
# at any time. Running it twice gives the same result (idempotent).
#
# What it sets:
#   1. Default branch "code" (integration, no deploys; alpha and beta
#      get it through PRs and releases; main is kept for production later).
#      Merge buttons: squash and rebase (the rulesets below decide which a
#      branch allows); a squash commit uses the PR title and body; the
#      branch is deleted after merge.
#   2. Rulesets "main" (code and main, squash merge) and "alpha" (rebase
#      merge, so each ticket's commits keep their own titles): changes only through a PR
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
#   5. Security features: secret scanning, push protection (a push that
#      contains a secret, such as an AWS key, is rejected), Dependabot
#      alerts and Dependabot security-update PRs.
#   6. Deployment environments: alpha (no gate) and beta (waits for the
#      owner's approval before any job that uses it starts).
#   7. Ruleset "release-branches": release/* branches (made by release.yml)
#      can't be force-pushed or deleted.
#
# Usage: Actions -> repo-settings -> Run workflow (repo-settings.yml), which
# runs this script with the ADMIN_TOKEN secret. The script itself needs the
# gh CLI, a repo-admin token and jq; DRY_RUN=1 only prints what it would send.
#
# Read the live settings back:
#   gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge
#   gh api repos/taracan/DevOpsSampleRun/rulesets

set -euo pipefail

REPO="taracan/DevOpsSampleRun"

# Checks that must pass before a PR can merge (job names from the workflows).
# Later phases add to this list.
REQUIRED_CHECKS=(
  build backend-lint backend-test frontend-lint frontend-test # ci.yml
  "analyze (python)" "analyze (javascript-typescript)" "analyze (actions)" # codeql.yml
  dependency-review                                      # dependency-review.yml
  pr-title                                               # pr-title.yml
)

GITHUB_ACTIONS_APP_ID=15368 # the checks must come from GitHub Actions
ADMIN_ROLE_ID=5             # built-in "Repository admin" role
OWNER_USER_ID=47918634      # taracan: approves beta deployments

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

# 1. Default branch and merge buttons
jq -n '{
  default_branch: "code",
  allow_squash_merge: true,
  allow_merge_commit: false,
  allow_rebase_merge: true,
  delete_branch_on_merge: true,
  squash_merge_commit_title: "PR_TITLE",
  squash_merge_commit_message: "PR_BODY"
}' | api PATCH "repos/$REPO"

# 2. Rulesets "main" and "alpha": the same rules, different merge button.
# Usage: branch_ruleset <name> <merge method> <branch pattern>...
branch_ruleset() {
  local name=$1 method=$2; shift 2
  jq -n --arg name "$name" --arg method "$method" \
    --argjson include "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    --argjson app "$GITHUB_ACTIONS_APP_ID" \
    --argjson checks "$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .)" '{
  name: $name,
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: { ref_name: { include: $include, exclude: [] } },
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
        allowed_merge_methods: [$method]
    } },
    { type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: true,
        required_status_checks: [ $checks[] | { context: ., integration_id: $app } ]
    } }
  ]
}' | put_ruleset
}
# Feature PRs into code: squash, one commit per PR, titled with its ticket.
branch_ruleset main squash "~DEFAULT_BRANCH" refs/heads/main
# Promote PRs into alpha: rebase, so each ticket's commits land unchanged
# and promote.yml can tell which tickets alpha already has.
branch_ruleset alpha rebase refs/heads/alpha

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

# 5. Security features
jq -n '{
  security_and_analysis: {
    secret_scanning: { status: "enabled" },
    secret_scanning_push_protection: { status: "enabled" },
    dependabot_security_updates: { status: "enabled" }
  }
}' | api PATCH "repos/$REPO"

# Dependabot alerts (needed for the security-update PRs above). Turning
# them on also enables the Dependency graph, which dependency-review.yml
# needs: without it that check fails with "not supported". No body.
if [[ "${DRY_RUN:-0}" == 1 ]]; then
  echo "--- PUT repos/$REPO/vulnerability-alerts"
else
  gh api --method PUT "repos/$REPO/vulnerability-alerts"
  echo "ok: PUT repos/$REPO/vulnerability-alerts"
fi

# 6. Deployment environments. Their variables are written by terraform.yml.
jq -n '{}' | api PUT "repos/$REPO/environments/alpha"

jq -n --argjson owner "$OWNER_USER_ID" '{
  reviewers: [ { type: "User", id: $owner } ],
  deployment_branch_policy: null
}' | api PUT "repos/$REPO/environments/beta"

# 7. Release branches
jq -n '{
  name: "release-branches",
  target: "branch",
  enforcement: "active",
  bypass_actors: [],
  conditions: { ref_name: { include: ["refs/heads/release/*"], exclude: [] } },
  rules: [ { type: "deletion" }, { type: "non_fast_forward" } ]
}' | put_ruleset
