# Workload configuration and plan review

Reviewed October 1, 2026 (America/New_York). This records the original pre-deployment review; no workload apply was performed by that review. Subsequent user applies partially created infrastructure and failed to deploy VMs; see [deployment troubleshooting](03-deployment-blockers.md) for current status.

## Execution context

Terraform 1.16.4, AzureRM 5.0.0, local Ubuntu execution, Azure Blob remote backend, isolated learning lab. Risk categories: testing blind spots, network blast radius, and provider/runtime consistency.

## Checks performed

- `terraform validate -no-color`: passed.
- `terraform fmt -check`: failed formatting check; identified `backend.tf`, `compute.tf`, `network.tf`, `terraform.tfvars`, and `vairables.tf`. This is formatting rather than a validation failure.
- `terraform plan -input=false -no-color -out=<private-plan-path>`: succeeded. Resource changes inspected through `terraform show -json` without publishing state, credentials, private input values, or the saved plan.
- Plan result: **30 resources to create; no updates or deletions**.

## Planned inventory

| Resource | Count |
| --- | ---: |
| Linux VMs | 5 |
| NICs | 5 |
| Subnets | 5 |
| NSGs | 5 |
| Subnet-to-NSG associations | 5 |
| VNet | 1 |
| Management public IP | 1 |
| Management SSH rule | 1 |
| Database managed data disk | 1 |
| Database disk attachment | 1 |

## VM findings

All five use Canonical Ubuntu 24.04 LTS (`server`, `latest`), one SSH public key, password authentication disabled, and 32 GiB Standard SSD LRS OS disks with ReadWrite caching. Management, web, app, and test use Standard_B2ls_v2; database uses Standard_B2s_v2. The database additionally has a 32 GiB Standard SSD LRS disk attached at LUN 0 with caching None.

VMs reference matching NIC map keys. NICs select subnets using each VM's `subnet_key`. Only the management NIC is configured to receive the Standard static public IP. The management NSG has an inbound TCP 22 rule for the configured administrator public IPv4 /32. All five subnet NSG associations are declared.

Successful planning does not prove regional capacity, successful provisioning, SSH connectivity, or runtime performance.

## Remaining work and accepted baseline

- Define an explicit outbound connectivity method for private VMs before depending on package installation, updates, or Azure monitoring endpoints. Current code contains no NAT gateway, load-balancer outbound configuration, or equivalent explicit path for the other four VMs. This review does not claim internet access works.
- Internal segmentation is intentionally deferred to a subsequent hardening phase. Default NSG VNet allow rules remain; all internal peers can attempt connections, subject to guest controls and authentication. Document baseline connectivity, then test the later allow/deny rules.
- Managed identities, shared tags, and boot diagnostics are absent from the VM definitions. Identities and permissions remain planned; tags should be added for ownership/cost reporting, and diagnostics are useful for troubleshooting.
- Format the files with `terraform fmt`, then validate and regenerate the final plan after further changes.
- The database disk still needs formatting, mounting, and PostgreSQL configuration after deployment.
- Verify VM-size availability and quota before apply; a successful plan does not reserve capacity.

## Next verification

```bash
terraform fmt
terraform validate
terraform plan -out=lab.tfplan
```

Review the complete regenerated plan before apply. Preserve bootstrap state and workload state ownership. No infrastructure or state mutation was performed by this review beyond normal plan locking/refresh; no rollback is required. Keep any plan artifacts private and out of Git.
