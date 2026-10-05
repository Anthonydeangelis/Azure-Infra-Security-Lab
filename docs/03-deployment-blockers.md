# Deployment troubleshooting: registration, quota, and SKU restrictions

Recorded October 1, 2026 (America/New_York). Terraform 1.16.4, AzureRM 5.0.0, local Ubuntu execution, Azure Blob workload state. This page preserves the failed applies and checks at that time. **October 2 update:** subsequent screenshots show five VMs deployed across two regions and connected peering in both directions. See [deployment verification](04-workload-deployment.md); earlier pending statements below are historical.

## Observed failures

1. Initial workload apply returned `MissingSubscriptionRegistration` for Microsoft.Compute and Microsoft.Network. Storage bootstrap did not enable these services automatically. Registration was advised; the later successful network-resource creation demonstrates progress, but registration status is not independently captured here.
2. Subsequent apply returned `SkuNotAvailable` for Standard_B2ls_v2 and Standard_B2s_v2 in East US 2.
3. A VM request returned `OperationNotAllowed` for Total Regional vCPUs: limit 4, usage 4 at the time of the request, additional request 2. That error's suggested limit 6 covered one operation, not the full five-VM design requiring 10 vCPUs.

The author reported a quota increase will not be approved. No approval/rejection document is included.

## Verified follow-up findings

Read-only inventory found no VMs in the workload resource group. Terraform state listed the VNet, five subnets, five NICs, five NSGs, five associations, management SSH rule/public IP, and database data disk. VM and database disk-attachment resources were absent. The partial apply therefore must not be described as a completed workload deployment.

East US 2 subsequently showed regional CPU usage 0, limit 4. The earlier transient usage 4 does not establish that two VMs were created. East US, Central US, North Central US, South Central US, and West US 2 also showed regional usage 0, limit 4, with inspected B-family limits of 4.

The subscription-specific SKU API reported location restrictions (`NotAvailableForSubscription`) in East US 2 for inspected B1/B2 candidates and D2as_v5/D2s_v5. This refines the earlier generic capacity error: these inspected sizes have subscription restrictions, not just an assumed temporary capacity shortage.

## Candidate alternatives (not yet deployed)

The following candidates had no reported SKU restrictions and family quota usage 0/limit 4 in East US 2, East US, and Central US:

| Size | vCPU | RAM |
| --- | ---: | ---: |
| Standard_F1als_v7 | 1 | 2 GiB |
| Standard_F1as_v7 | 1 | 4 GiB |
| Standard_D2as_v7 | 2 | 8 GiB |

Quota and restriction checks do not reserve capacity or prove provisioning succeeds. Prices, regional image availability, image/VM storage-controller compatibility, managed disk support, and deployment behavior must be checked before selecting replacements.

A proposed layout is four one-vCPU workload VMs (management, web, app, database) in East US 2 and a one-vCPU test VM in East US. This fits regional limits but reduces database sizing from the original design and needs workload testing. It adds a second VNet, non-overlapping address space, NSG, test NIC, and bidirectional global VNet peering. Cross-region traffic and alternative compute pricing need cost review. This remains a proposal, not an implemented architecture.

## Design history checkpoint

Recorded October 2, 2026. The local Git tag `design-before-region-refactor` preserves the files as they stood before the planned region-aware map refactor. This is the repository's first commit, not a reconstruction of an earlier configuration.

**Original design:** five Linux VMs in East US 2, with management, web, application, database, and test subnets in one VNet. The original two-vCPU VM sizes would require ten regional vCPUs.

**Reason for the pivot:** the subscription had a four-vCPU regional limit and restrictions on the requested VM sizes. A quota increase was reported unavailable. The proposed alternative keeps four one-vCPU VMs in East US 2 and places the test VM in a second region with a separate VNet and bidirectional peering. Candidate sizes and the revised deployment remain unverified.

**What this checkpoint contains:** the original single-region resource structure, bootstrap configuration, documentation, and reviewed screenshots, plus an unfinished second-VNet block already added by the author. That block has a leading space in its location and a string rather than a list for its address space. It is preserved unchanged as work in progress; the checkpoint is not a validated, fully deployed release. Private input files, state, caches, and saved plans are excluded.

**Next change:** use named VNet maps, subnet `vnet_key` references, and derived VM/NIC locations. Preserve the existing primary VNet's identity and inspect all proposed replacements before applying. Commit the completed refactor separately so reviewers can compare it with this checkpoint.

To inspect the checkpoint and compare subsequent changes locally:

```bash
git show design-before-region-refactor:Terraform/network.tf
git diff design-before-region-refactor HEAD -- Terraform/
git log --oneline --decorate
```

Git records configuration history; it does not back up Terraform state or restore deleted Azure resources. No Azure changes or state operations are part of this checkpoint. A GitHub commit comparison link can be added after the repository is connected and the refactor is committed.

## Recovery and validation plan

- Preserve current Azure backend state, deployed network resources, and database disk.
- Confirm current state/inventory again before editing; quota availability can change.
- Check candidate costs and image/disk compatibility.
- Keep VM map keys stable while changing sizes and adding explicit regional placement.
- Ensure each VM, NIC, subnet/VNet, and attached managed disk have consistent regional placement.
- Define the new region's subnet range without overlap, peer the VNets both ways, and update SSH/application access rules.
- Plan the test NIC replacement explicitly; do not simply change the global location variable and replace the entire stack.
- Finish outbound access design before relying on guest updates or agents.

```bash
terraform fmt -check
terraform validate
terraform plan -out=lab.tfplan
```

Review all creates/replacements/deletions before applying the new plan. Verify five VMs, correct placements, state tracking, SSH through management, and cross-region connectivity after a successful apply.

Risk categories: partial-apply recovery, identity churn, blast radius, and testing blind spots. No infrastructure modifications were performed by the diagnostic checks. Preserve state and data if a retry fails. Reverting configuration alone cannot restore resources deleted by a later apply, so review replacements before execution. Do not publish saved plans, private inputs, raw subscription identifiers, or state contents.
