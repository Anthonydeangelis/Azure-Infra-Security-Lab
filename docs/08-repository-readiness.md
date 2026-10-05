# Repository setup and publication review

Reviewed October 5, 2026. This repository demonstrates an in-progress learning lab. Sentinel, incident response, complete segmentation, explicit outbound connectivity, backup/restore, policy, budget alerts and OIDC CI/CD are not claimed complete.

## Execution context

Terraform 1.16.4 and pinned AzureRM 5.0.0; workload state uses Azure Blob with Entra authentication. Bootstrap owns the state storage, role assignment and resource groups. Workload references the existing group and owns workload resources. Ansible runs on the Mac using local SSH configuration and private keys outside Git.

## Private inputs and setup

Reviewed examples are provided at [workload inputs](../Terraform/terraform.tfvars.example) and [bootstrap inputs](../bootstrap/terraform.tfvars.example). They use a zero GUID, documentation-only IP, and explicit placeholders for identity/key/storage values. VM sizes and regions illustrate this author's subscription constraints; availability and pricing must be checked for a new subscription.

1. Install the verified Terraform/provider versions, Azure CLI, and authenticate to the intended subscription. Register required providers, including Microsoft.Compute, Microsoft.Network, Microsoft.Storage, Microsoft.OperationalInsights and Microsoft.Insights.
2. Copy each example to that root's private `terraform.tfvars`; replace placeholders and review all values. The existing backend account name in `Terraform/backend.tf` identifies this lab and is not a credential. For a separate deployment, configure your own backend before initialization. Never accidentally use the author's live state or let two states own one resource.
3. Bootstrap is initialized separately and currently uses local state. Review its plan before applying and keep an encrypted backup of its state outside Git. The bootstrap provider uses the selected Azure CLI subscription; confirm it matches your intended subscription.
4. Initialize the workload backend only after storage and access exist. For this existing lab, do not rebootstrap or migrate state just to publish the repository.
5. From each Terraform root, run `terraform fmt -check`, `terraform validate`, and review `terraform plan -out=lab.tfplan` before apply. Saved plans stay private. Plan/apply are operational steps, not required to view the portfolio.
6. Run Ansible using a private inventory and local SSH alias as documented in [Ansible setup](05-ansible-web-configuration.md). Do not commit connection settings or private keys.

Some resources and variables are learning-stage placeholders. Empty Terraform files represent planned components, not implemented features. Inputs including state-storage names are retained even where not consumed by workload resources.

## Publication review scope

- Reviewed tracked files, publishable untracked files, and the one existing commit's tracked file list. No state, real tfvars, saved plans, private keys or Terraform caches are tracked in that history.
- Pattern-based text checks found no private-key blocks, Azure account-key connection strings, GitHub token patterns, real GUID identifiers or email addresses in publishable file contents. This is a bounded review, not a guarantee that every possible secret format can be detected. Dedicated secret-scanner/OCR tools were not installed.
- Reviewed screenshot evidence supplied during the walkthrough. Lab private addresses, lab usernames and Azure resource names are retained as noncredential evidence. Heartbeat screenshots with public addresses/identifiers and the portal image with account details were kept out of the repository; sanitized replacements remain pending.
- Git commit metadata contains the author's configured email. It is separate from file contents and will be public if the existing history is pushed. Decide whether to retain it or sanitize the unpublished history before a public push. No history rewrite was performed during this review.
- A remote is already configured. No push, Azure deployment, Terraform state operation or resource change was performed as part of the publication review. Formatting and documentation changes do not change infrastructure behavior.

## Evidence gaps and security limitations

Some earlier inventory/bootstrap screenshots are visible only in conversation and unavailable in the repository. They are documented as pending copies rather than embedded with broken links. Author-confirmed checks without screenshots are labeled accordingly.

The storage bootstrap code does not explicitly configure all planned recovery/hardening controls; verify anonymous access, HTTPS, versioning, soft delete, exception details and state backup before claiming hardened state storage. General VM outbound filtering remains broad. The 1-GB workspace cap does not provide a spending limit. Syslog marker and AzureActivity ingestion tests remain pending despite general Heartbeat/Syslog ingestion.

These limitations do not prevent presenting the work honestly as an in-progress portfolio project; they prevent presenting it as fully hardened or fully reproducible production infrastructure.
