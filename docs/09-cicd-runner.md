# Private CI/CD runner setup

October 5, 2026. The development repository remains private. The author plans to create a separate sanitized public portfolio repository after completing the lab. The existing runner is for trusted private-repository workflows; public publication and runner registration are separate steps.

## Verified runner registration

The supplied screenshot shows `./run.sh` launched from `~/actions-runner` on Ubuntu under `labadmin`, connected to GitHub, runner version 2.337.0, and **Listening for Jobs** at 18:16:05 UTC. This verifies connection/readiness, not execution of a workflow or Azure access.

![Self-hosted runner connected and listening](../screenshots/cicd/01-runner-listening.png)

The initial screenshot captures an interactive runner. The author subsequently reported moving it to `/home/github-runner/actions-runner`, installing the service as `github-runner`, and confirming service/tool checks. Those later checks have not yet been captured as evidence. Registration credentials and runner working files must never be committed.

## Isolation and identity

The runner initially used the everyday development account. Its reported dedicated account avoids using that account directly, but access to development files still depends on filesystem permissions. OIDC alone does not isolate local files or cached credentials.

Use a separate Entra application/service principal for this lab pipeline; do not reuse or alter the previous Entra automation project's identity. Authenticate using a narrowly scoped GitHub federated credential, not a client secret or the author's interactive Azure login. Verify the repository's actual OIDC subject format before configuring trust.

## Next implementation stages

1. Isolate the runner account and verify required tools/network access under it.
2. Create the dedicated Azure deployment identity and federated trust for this private repository and intended workflow context.
3. Assign workload-scoped permissions and container-scoped Storage Blob Data Contributor for backend access. Ordinary Contributor does not grant role-assignment creation; add only the access needed for actual pipeline resources. Subscription Activity Log export requires separate subscription-level authorization and should remain administrator-managed unless explicitly delegated.
4. Start with a trusted, manually triggered validation/plan workflow. Provide private inputs without committing them, pin tool/action versions, and isolate Azure authentication from personal CLI configuration.
5. Implement a reviewed saved-plan apply with an approval mechanism supported by the repository's GitHub plan. Do not assume private-repository environment reviewer gates are available.
6. Run and capture a successful job, plan review, and approved apply before marking CI/CD complete.

Keep saved plans private and short-lived; they may contain sensitive values. Restrict runner execution to trusted code. Do not execute untrusted pull-request changes on this persistent host. Network access to state storage and identity authorization are independent requirements.

## Initial OIDC test

The author reports creating the Entra federated credential, assigning Azure permissions, and adding `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` as repository secrets. The storage role screenshot shows inherited access from a parent scope, rather than a container-only assignment.

The workflow [Azure OIDC login test](../.github/workflows/azure-login-test.yml) runs manually on `main` using the Linux x64 self-hosted runner. It checks the dedicated account, authenticates with a pinned Azure Login action, and reads the lab resource group. It uses a temporary Azure CLI configuration and cleans it up. No repository checkout is required.

Push the workflow to `main`, then select **Actions → Azure OIDC login test → Run workflow**, with `main` selected. A successful run verifies authentication and resource-group read access only. State-container access, Terraform plans, subscription diagnostic-setting access, and applies remain unverified. This workflow does not run Terraform; the existing Terraform 1.16.4 / AzureRM 5.0.0 / Azure Blob backend configuration is unchanged.

GitHub OIDC requires `id-token: write`; see [GitHub's Azure OIDC guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure). The initial successful test used pinned Azure Login v2. After reviewing its Node.js 20 deprecation warning, the workflow was upgraded to pinned Azure Login v3, which declares Node.js 24. A successful rerun of the upgraded workflow remains pending. See [Azure Login](https://github.com/Azure/login).

## Successful login evidence

On October 5, the supplied screenshot shows **Azure OIDC login test #2**, attempt 5, succeeded in 11 seconds. The dedicated runner-account check, OIDC authentication, service-principal/resource-group check, and cleanup steps succeeded. Two annotations are marked as warnings. The subsequently supplied text identifies a Node.js 20 deprecation warning for Azure Login v2; the other annotation's message was blank in the supplied text and remains unidentified.

![Successful Azure OIDC login test](../screenshots/cicd/02-oidc-login-success.png)

The initial login failure was a case-sensitive federated-subject mismatch in the GitHub owner name. Recreating only the credential with the exact subject emitted by GitHub corrected the capitalization. Azure persisted the corrected subject before the successful rerun. The app registration and role assignments were preserved.

This confirms authentication and resource-group read access, not storage data-plane access or infrastructure write permissions. Next verify state-container access, then add Terraform validation and a reviewed plan. No Terraform apply has run through CI.

## Manual Terraform plan workflow

[Terraform validate and plan](../.github/workflows/terraform-plan.yml) is implemented but has not yet run in GitHub. It only accepts manual runs on `main` in the private repository. It checks the dedicated runner account and installed Terraform version (1.16.4), checks out the selected commit without persistent Git credentials, checks formatting, loads private inputs, logs in through OIDC, checks the existing state blob, initializes with the committed lockfile, validates, and generates a saved plan. AzureRM remains pinned to 5.0.0. Automatic provider registration is disabled; an administrator must register required namespaces, including `Microsoft.SecurityInsights` for Sentinel.

### Before running

Add a repository secret named **TERRAFORM_TFVARS** containing the complete current workload `Terraform/terraform.tfvars` contents, not the sanitized example or bootstrap inputs. Preserve the deployed username, SSH public key, network definitions and other values to avoid unintended changes. Never include an SSH private key or client secret. Do not commit the input file. If using an authenticated GitHub CLI from the repository, `gh secret set TERRAFORM_TFVARS < Terraform/terraform.tfvars` transfers the contents without printing them.

The existing three `AZURE_*` secrets are reused. The runner needs outbound access to GitHub, Azure identity/management endpoints, the provider registry, and the storage blob endpoint. The storage firewall must allow the runner's actual public egress address independently of its Blob Data Contributor role.

The full workload root includes a subscription-level Activity Log diagnostic setting. Lab resource-group Contributor does not cover subscription-scoped reads. If refresh fails with authorization errors, provide the specific read access reported (such as `Microsoft.Insights/diagnosticSettings/read`) through a suitable subscription-scoped read role, or deliberately separate management of that setting in a later reviewed state migration. Do not grant subscription Contributor simply to make a plan pass. Future changes to the subscription setting require additional write authorization; this workflow does not apply them.

### Run and review

Commit and push the workflow to `main`, then select **Actions → Terraform validate and plan → Run workflow → main**. It plans the entire workload root, including Sentinel, rather than targeting one resource. Successful exit code 2 means changes were found; 0 means no changes. Failures remain failures.

Download the run's `terraform-plan-<run-id>-<attempt>` artifact and inspect `plan.txt`. A successful artifact also contains `lab.tfplan` and commit/run provenance. Failed plan output is retained for diagnosis. All of these files are private and expire after one day; plans and diagnostic output may contain sensitive infrastructure data. Repository users with artifact access can read them. Do not publish them in the portfolio repository.

Temporary inputs, backend working files, plan files and the Azure CLI session are removed from the runner after the run. The plan uses state locking and queued workflow concurrency; avoid a simultaneous local apply. No deployment is performed. Review any replacements or deletions before proceeding. Approval and consuming the exact reviewed plan will be implemented separately.

Local checks passed for YAML, embedded Bash syntax, Terraform formatting and Terraform validation. Azure-connected execution, storage permissions, and a successful CI plan remain unverified. Removing the workflow disables this manual CI entry point without changing deployed Azure resources. A plan may acquire and release a state lease; it is not an infrastructure apply.
