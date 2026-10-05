# Azure Infrastructure & Security Lab

A hands-on project demonstrating Azure administration, Terraform, and practical cloud security automation.

**The project story:** deploy a small Azure environment, secure it, collect its logs, detect a security-relevant change, and automate investigation and response.

## Current status

**Initial compute and networking deployed across two regions.** Screenshots reviewed October 2, 2026 show five VMs, two non-overlapping VNets, connected peering in both directions, and the database data disk attached. The author reports successful SSH to management; the supplied login screenshot shows Ubuntu 24.04.4 LTS. October 3 evidence verifies management-to-app and cross-region management-to-test SSH. All four private VM SSH destinations are now evidenced. Explicit outbound access, broader segmentation, and security automation remain pending. Initial management/web monitoring is now collecting Heartbeat and general Syslog. See [deployment verification and remaining tests](docs/04-workload-deployment.md).

See [Bootstrap deployment and evidence](docs/01-state-storage-bootstrap.md).

**Ansible web configuration verified October 3, 2026:** Nginx installed from the Mac through the management jump host. The repeat run reported **changed=0**, and management received **HTTP 200** from the private web VM. [Commands, results, and screenshots](docs/05-ansible-web-configuration.md). Explicit outbound configuration and the broader security automation remain pending.

The custom lab homepage is also deployed through Ansible: **5 OK, 1 changed** on deployment and **5 OK, 0 changed** on repeat, with no failed or unreachable tasks. Management retrieved the expected HTML over private HTTP. [Custom-page evidence](docs/05-ansible-web-configuration.md#custom-homepage-verified-october-3-2026).

**Post-deployment check, October 3, 2026:** the supplied Terraform plan reports **No changes**. [Screenshot and verification limits](docs/04-workload-deployment.md#follow-up-plan-verified-october-3-2026).

**Web NSG decisions verified:** the reviewed plan proposed three inbound rules (**3 additions, 0 changes, 0 deletions**). Network Watcher now reports management SSH/HTTP allowed by the explicit rules and app SSH/HTTP denied by `Deny_All`. Live HTTP tests also show management retrieving the custom page while app times out. The author also confirmed fresh web SSH still worked and the post-change plan reported no changes; those final checks have no retained screenshots. The apply summary remains uncaptured. [Before/after design, plan, and test checklist](docs/06-web-network-segmentation.md).

[Workload review](docs/02-workload-plan-review.md) records the original pre-deployment plan. The revised saved plan was reviewed with **13 additions, 0 updates, and 4 replacements of test-network resources**; the primary VNet and database disk were preserved in that plan. Actual apply totals have not yet been captured.

[Deployment troubleshooting](docs/03-deployment-blockers.md) records the earlier quota and SKU failures that prompted the redesign. Subsequent inventory screenshots now show all five VMs using Standard_F1as_v7 across East US 2 and East US.

Completed items will be checked off only after testing. Screenshots and short explanations will document the results, including any limitations.

**Design history:** the local Git tag `design-before-region-refactor` preserves the earlier code, including an unfinished second-VNet block. [Original design, reason for the pivot, and checkpoint limitations](docs/03-deployment-blockers.md#design-history-checkpoint) are documented separately. The revised compute/network deployment is now evidenced; functional testing remains in progress.

```text
East US 2: vnet-lab01 (10.50.0.0/16)
  Management, web, app, database VMs
             ↕ Connected VNet peering
East US:   vnet-lab02 (10.60.0.0/16)
  Test VM
```

All five VMs use Standard_F1as_v7. October 3 screenshots verify management-to-app SSH within the primary VNet and management-to-test SSH across peering. See [connection commands and evidence](docs/04-workload-deployment.md#primary-vnet-ssh-verified-october-3-2026). Additional screenshots verify management-to-web and management-to-database SSH; all four private destinations are now tested. Web inbound restrictions are verified separately in the segmentation evidence above.

**Initial monitoring verified October 3, 2026:** `law-azure-sec-lab` contains Heartbeat and general Syslog from management and web. The successful retry apply added four resources. The specific controlled Syslog message and AzureActivity ingestion are not yet verified. [Monitoring setup, evidence, and troubleshooting](docs/07-initial-monitoring.md).

## Planned architecture

```text
GitHub Actions + OIDC → Terraform → Azure lab resources
                                    ├── Virtual network, subnets, and NSGs
                                    ├── VM workload and managed identity
                                    ├── Storage and Key Vault
                                    └── Security controls and backup

Activity Log + selected resource/VM logs → Log Analytics
                                           ├── Azure Monitor alerts
                                           └── Microsoft Sentinel
                                                → Incident
                                                → Playbook enrichment + notification
```

The current deployed baseline is documented above. OIDC, Key Vault, alerts, backup, Sentinel, and playbook response remain planned; this diagram shows the intended end state. Cost estimates and state recovery tests remain unfinished.

## Project breakdown

### 1. Terraform infrastructure

**Goal:** deploy a small environment that can be reproduced and managed through code.

- [x] Review and adapt the initial architecture to regional quota and SKU constraints.
- [ ] Define naming, tags, resource ownership, and remote state.
- [x] Deploy the bootstrap storage account and blob container.
- [x] Verify selected-network access is configured (exception details still pending).
- [x] Initialize the workload Azure backend and confirm the remote state blob exists.
- [x] Deploy networking and five Linux VMs across two regions.
- [ ] Complete workload storage, Key Vault, and scoped identity/access tests.
- [ ] Configure GitHub Actions authentication with OIDC.
- [x] Verify VM inventory, private SSH paths, and a follow-up no-changes plan.

**Evidence:** architecture and deployed-resource notes, sanitized plan summary, private SSH tests. GitHub workflow evidence is planned.

### 2. Secure administration

**Goal:** demonstrate controlled access, network protection, cost awareness, and recovery.

- [ ] Configure and test scoped RBAC assignments.
- [x] Verify web NSG management allows and app denial; document SSH through management.
- [ ] Extend segmentation to remaining workload subnets.
- [ ] Configure appropriate private access for selected services.
- [ ] Apply Azure Policy and review compliance results.
- [ ] Configure a budget and alert notifications.
- [ ] Configure VM backup and complete a tested restore.

**Evidence:** allowed/denied access tests, network rules, policy results, budget configuration, and restore validation.

### 3. Operational monitoring

**Goal:** collect useful logs and demonstrate that monitoring works.

- [x] Deploy Log Analytics and subscription Administrative Activity Log export.
- [ ] Verify a lab event arrives in AzureActivity.
- [ ] Enable selected resource diagnostic settings.
- [x] Collect Heartbeat and general Linux Syslog from management and web using AMA and a DCR.
- [ ] Verify a uniquely tagged controlled Syslog event.
- [ ] Extend guest monitoring to the remaining VMs and collect Nginx access/error files.
- [ ] Save KQL queries for resource changes and workload health.
- [ ] Trigger and verify an operational alert.

**Evidence:** incoming log records, query results, and a tested alert.

### 4. Security monitoring

**Goal:** investigate an NSG change using Microsoft Sentinel.

- [ ] Enable Sentinel and verify the selected data sources.
- [ ] Create an isolated test NSG with no subnet or network interface attached.
- [ ] Generate a controlled rule change without exposing a workload.
- [ ] Create and test a detection that produces a Sentinel incident.
- [ ] Investigate the actor, resource, time, operation, and actual rule configuration.
- [ ] Test an expected change as well as a suspicious configuration.
- [ ] Remove the test rule and document the outcome.

**Evidence:** controlled event, Activity Log record, detection query, incident, and investigation walkthrough.

An NSG write is a change signal, not proof of dangerous access. The investigation will inspect rule direction, action, priority, source, destination, ports, and NSG associations. Current configuration may differ from the configuration at event time; that limitation will be recorded.

### 5. Investigation automation

**Goal:** enrich an incident and notify me using a Sentinel playbook.

- [ ] Document the playbook identity and minimum required permissions.
- [ ] Retrieve the affected NSG and its current rules and associations.
- [ ] Add investigation findings to the incident.
- [ ] Send and verify a notification.
- [ ] Test failure handling, including missing resources or denied access.

**Evidence:** playbook run, incident enrichment, notification, and a failure-handling test.

**Later, optional:** approval-required remediation restricted to explicitly tagged lab resources; scheduled shutdown of tagged VMs; or an inventory/compliance report. Automatic remediation is outside the initial scope.

## Reproducing the configuration

See [setup and publication notes](docs/08-repository-readiness.md). Sanitized input examples are provided in both Terraform roots; real inputs, keys, state and plans stay private. This is an in-progress portfolio lab, not a production-ready deployment template.

## Repository layout

`bootstrap/`, `Terraform/`, `ansible/`, `docs/`, and `screenshots/` exist. The monitoring, Sentinel, and automation folders are planned.

```text
bootstrap/     Separate state-storage creation configuration
Terraform/     Workload infrastructure and monitoring resources
ansible/       Linux server configuration playbooks
monitoring/    KQL queries and operational alert definitions
sentinel/      Detection rules and investigation examples
automation/    Playbook definitions and supporting scripts
docs/          Architecture, decisions, permissions, costs, and troubleshooting
screenshots/   Sanitized evidence organized by phase
```

## Verified results

Evidence reviewed September 30–October 3, 2026 from author-supplied screenshots and reported checks. The following table summarizes bootstrap; later milestones are linked above. Screenshot filenames use local time, while some Azure records display UTC.

| Step completed | Observed result | Evidence |
| --- | --- | --- |
| Bootstrap apply | Storage account and container created; **2 added, 0 changed, 0 destroyed** | [Apply evidence notes](docs/01-state-storage-bootstrap.md#1-terraform-apply) |
| Resource placement | Storage account visible in the dedicated state resource group, East US 2 | [Resource overview notes](docs/01-state-storage-bootstrap.md#2-resource-group-overview) |
| Storage network configuration | Selected networks enabled; one IPv4 entry and one exception displayed | [Networking screenshot](screenshots/bootstrap/03-storage-networking.png) |
| State-access RBAC | Role assignment apply: **1 added, 0 changed, 0 destroyed**; Storage Blob Data Contributor visible in IAM | [RBAC evidence notes](docs/01-state-storage-bootstrap.md#4-state-access-role-assignment) |
| Workload backend | Azure backend initialized successfully; `azure-lab.tfstate` block blob visible in the portal | [Remote-state evidence notes](docs/01-state-storage-bootstrap.md#5-workload-backend-initialization) |

### Remote-state evidence

Azure backend initialization completed successfully, and the state blob is visible in the storage container.

![Successful Azure backend initialization](screenshots/bootstrap/06-backend-initialization.png)

![Remote Terraform state blob in Azure Storage](screenshots/bootstrap/07-remote-state-blob.png)

For each update, record **what changed, how it was tested, what happened, and a link to the evidence**. Include unsuccessful tests and their fixes when they demonstrate useful troubleshooting.

## Evidence and documentation

- Use descriptive screenshot names, such as `01-resource-overview.png` and `04-sentinel-incident.png`.
- Capture the configuration and its tested result; a setup screenshot alone does not prove success.
- Redact sensitive identifiers, account details, IP addresses where necessary, and notification recipients before committing evidence.
- Never commit credentials, private keys, Terraform state, saved plans, or private configuration. Review the repository exclusions before the first push.
- Keep detailed notes in `docs/` as needed and link to them from the completed phase.

## Costs and cleanup

Before deploying, document the region, VM size, expected runtime, log ingestion and retention, and estimated service costs. Review backup, Sentinel, private connectivity, and automation costs as each is introduced.

Budget alerts provide notification; they do not impose a hard spending limit. Record a shutdown and cleanup procedure, including resources that continue to incur charges after a VM is stopped. Protect state and retained evidence during cleanup.

## Project boundaries and related work

This lab builds on my previous Entra ID and Azure Automation work with PowerShell, Microsoft Graph, managed identities, Blob Storage, Key Vault, and GitHub Actions OIDC.

The Entra automation and Proxmox Terraform projects remain separate. Their resources will not be recreated or modified unnecessarily. Each managed resource must have one Terraform state owner; this project will not place an existing resource under a second state.

Links to those projects will be added when ready. Completion claims in this README apply only to evidence verified for this lab.
