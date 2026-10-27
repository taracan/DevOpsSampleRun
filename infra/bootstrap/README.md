<!--
  README.md (infra/bootstrap): the one-time setup that has to exist before
  GitHub Actions can run Terraform (infra/backend/ and infra/frontend/),
  done by hand in the web consoles.
-->

# One-time setup (web consoles, done once)

A workflow can't create the role it signs in with, so these few pieces are
made by hand. Everything after this runs from GitHub Actions.

Already in place from earlier steps: the Terraform state bucket
`smallproject-tfstate-631571737116` (its local state, `terraform.tfstate`
in this folder, is not committed) and the GitHub OIDC identity provider.

## 1. AWS IAM console: the Terraform role

IAM → Roles → **Create role** → **Custom trust policy**, paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::631571737116:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": [
            "repo:taracan@47918634/DevOpsSampleRun@1410627250:environment:dev",
            "repo:taracan@47918634/DevOpsSampleRun@1410627250:environment:beta"
          ]
        }
      }
    }
  ]
}
```

Next → attach **AdministratorAccess** → name it `smallproject-terraform` →
Create. Only jobs in this repo's `dev` or `beta` GitHub environment can use it.

Already made it trusting only `dev`? IAM → Roles → `smallproject-terraform`
→ **Trust relationships** → **Edit trust policy**, paste the text above,
**Update policy**.

## 2. GitHub: a token for repo settings and variables

github.com → your avatar → Settings → Developer settings → Personal access
tokens → **Fine-grained tokens** → Generate:

- Repository access: only `taracan/DevOpsSampleRun`
- Repository permissions, **Read and write**: Administration, Contents,
  Environments, Variables, Workflows
- Expiration: your choice (renew it here when it expires)

Then in the repo: Settings → Secrets and variables → Actions:

- **Secrets** → New repository secret `ADMIN_TOKEN` = the token
- **Variables** → New repository variable `TF_ROLE_ARN` =
  `arn:aws:iam::631571737116:role/smallproject-terraform` (a repository
  variable serves dev and beta; one already set on the `dev` environment
  is fine to keep, it has the same value)

## 3. GitHub Actions: first runs

1. Actions → **repo-settings** → Run workflow. Creates the `dev` and `beta`
   environments (beta waits for your approval), the release-branch rule and
   the `pr-title` required check.
2. The merge that splits Terraform into `infra/backend/` and
   `infra/frontend/` runs **deploy-backend** and **deploy-frontend** for dev.
   Each applies its own stack first, which fills dev's variables, then
   deploys. The frontend stack takes over dev's existing bucket and
   CloudFront distribution (`moved.tf` in both stacks); nothing is rebuilt.
3. AWS console → CloudFront → **Origin access** → select the old
   `smallproject-web` (the distribution now uses `smallproject-web-oac`) →
   **Delete**. The console refuses if it's still in use.
4. Beta: Actions → **release**, which applies both stacks to beta (backend
   first) and deploys. Or Actions → **terraform**, stack `backend` then
   `frontend`, env `beta`, action `apply` → approve.
