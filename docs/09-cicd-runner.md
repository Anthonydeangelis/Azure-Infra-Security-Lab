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
