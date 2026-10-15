# Repository review

Reviewed October 15, 2026: publishable source, examples, workflows, documentation, 57 reachable Git commits, and all 37 committed screenshots. The README records the completed lab and links to the test evidence; dated runbooks preserve the build history.

## Verified work

- Five Azure VMs, peered networking, Blob-backed Terraform state, and private administration through management.
- Ansible-managed Nginx with a no-change repeat run; Unbound resolution tested over UDP and TCP.
- Azure Activity and guest Syslog ingestion into Log Analytics.
- DNS reputation, NSG changes, and invalid-user SSH activity each producing an alert-backed Defender incident and automatic email.
- GitHub OIDC authentication and reviewed saved-plan deployment workflows.

The included Unbound role recreates the documented configuration. The original Mac-local role was tested live; the included version passes local checks and has not been deployed. This distinction does not change the results shown in the original screenshots.

## Repository corrections

Added the missing DNS playbook/role, safe inventory and SSH examples, and control-node instructions. Completed required example inputs, corrected the variables filenames, removed empty Terraform placeholders, and updated stale documentation. Both roots now declare Terraform 1.16.4; bootstrap uses its declared subscription input. All Azure-connected jobs require private `main` execution.

These edits do not rename Terraform resource addresses. No state migration or Azure apply was performed during this review.

## Checks completed

| Check | Result |
| --- | --- |
| Terraform 1.16.4 / AzureRM 5.0.0 | Formatting and validation pass for both roots |
| Example inputs | Required inputs present; real values remain private |
| Ansible Core 2.19.3 | Both playbooks pass syntax checks; inventory parses; YAML lint passes |
| Unbound 1.19.2 | Rendered configuration passes its native checker with local filesystem/user defaults adjusted for the review host |
| CI helpers | Seven saved-plan verification tests pass |
| Workflow review | YAML and shell syntax pass; external actions are commit-pinned; private-main guards verified |
| Documentation | Local links and screenshot targets resolve |

Local checks do not replace a live deployment test.

## Sensitive-data review

All 37 PNGs were inspected visually and with OCR, including their embedded metadata. No location or private-path metadata was found. No visible API keys, access tokens, passwords, private keys, or personal mailbox addresses were found. Existing redactions remain intact. The public IPs in the DNS lookup images are returned DNS answers. Lab names, private IPs, author display name, and Azure resource identifiers remain visible as evidence; these do not grant access.

Gitleaks 8.30.1 scanned the 57 reachable commits and the publishable working tree. The only findings were the literal KQL field name `FailedPasswordCount`, confirmed as false positives. No credential values were detected. An exact comparison also found no copy of the current private VT key in publishable files, screenshot text, or reachable historical blobs. Ignored private tfvars, state, plans, keys, caches, and local connection files are excluded from the push. Git commit metadata retains the configured author identity. These checks reduce exposure risk; they cannot prove that every possible secret format is absent.

Personal email screenshots supplied during validation remain outside the repository.

**Outstanding credential cleanup:** the author confirmed the VirusTotal key has not been rotated. It previously appeared in private plan output before the input was marked sensitive. No copy was found in the reviewed repository files or screenshots. Invalidate it at VirusTotal and handle old private logs/artifacts during cleanup; deleting Azure resources does not deactivate an external API key. This review does not claim that cleanup has occurred.

## Remaining boundaries

The DNS workflow deliberately selects one test domain and one result per run. Broader coverage needs quota handling and recovery. The SSH password-failure branch is untested, web-tier segmentation is the demonstrated network boundary, and database setup, budgets, backups, and recovery testing remain outside the completed scope.

A license has not been selected. Repository visibility remains unchanged. Public copies skip Azure-connected jobs; trusted runner access, repository secrets, and retained Actions artifacts should remain private.

[README](../README.md) · [Ansible guide](../ansible/README.md) · [CI runbook](09-cicd-runner.md) · [Security automation runbook](10-dns-and-security-automation.md)
