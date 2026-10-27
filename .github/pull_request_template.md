<!--
  pull_request_template.md: GitHub pre-fills every new pull request with
  this text. Replace the prompts below and tick the checklist. Lines inside
  these comment markers don't show up in the published PR.
-->

<!-- Title: start with the Jira ticket number, e.g. "SI-12 Supplier sync". -->

## Jira
<!-- Link to the ticket. -->

## What / Why
<!-- What does this PR change, and why is it needed? -->

## How tested
<!-- Commands you ran, pages you clicked through, what you checked. -->

## Checklist
- [ ] Lint and tests pass locally
- [ ] Infra changes (if any): the `terraform` plan on this PR shows what will change
- [ ] No secrets committed (keys, passwords, `.env` files)
