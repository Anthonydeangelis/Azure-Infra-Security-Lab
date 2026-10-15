# Linux workload configuration

Terraform provisions Azure resources; Ansible configures the guest services. Run these playbooks from a trusted controller with SSH access through management. Keep private keys on the controller; ProxyJump does not require copying them to management.

| Playbook | Purpose | Verification |
| --- | --- | --- |
| `web.yml` | Install Nginx, manage the homepage, and check HTTP | Live-tested, including a repeat run with zero changes |
| `dns.yml` | Install/configure Unbound through `roles/unbound` | Recreates the documented Mac-local configuration; local checks pass, but this included version has not been deployed |

The DNS screenshots show the original live-tested Mac-local role.

## Setup

Use Python 3.11+ and the pinned controller requirements:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r ansible/requirements-control.txt
cp ansible/inventory.example.ini ansible/inventory.local.ini
```

Replace the example username, public IP, and SSH key path. Adapt `ssh_config.example` into your private `~/.ssh/config`; its management alias must match the inventory's jump-host alias. Verify server host-key fingerprints through trusted access. Do not disable host-key checking.

The example private addresses match this lab. For another deployment, check the actual NIC addresses; allocation is currently dynamic.

## Check and run

Inspect the inventory and syntax first:

```bash
ansible-inventory -i ansible/inventory.local.ini --graph
ansible-playbook -i ansible/inventory.local.ini ansible/web.yml --syntax-check
ansible-playbook -i ansible/inventory.local.ini ansible/dns.yml --syntax-check
```

Configure the intended lab hosts:

```bash
ansible-playbook -i ansible/inventory.local.ini ansible/web.yml
ansible-playbook -i ansible/inventory.local.ini ansible/dns.yml
```

Before replacing an existing resolver configuration, back it up and check for conflicting listener or root-forwarding definitions. The role writes `/etc/unbound/unbound.conf.d/azure-lab.conf`; it does not remove other fragments. It validates configuration and restarts the service through a handler. If the complete check fails, correct the conflict or restore the backup before restarting.

Optional `--check --diff` previews changes, but a fresh host may lack `unbound-checkconf` until the package is installed. Syntax/check mode alone does not prove runtime behavior.

## DNS behavior

- Listen on localhost and `10.60.1.4`, UDP/TCP port 53.
- Allow localhost and management `10.50.1.4/32`; refuse other clients.
- Forward to Azure DNS `168.63.129.16` and log queries through Syslog.

Override the role defaults through private host/group variables when needed. The role configures Unbound; Azure NSGs, client DNS settings, and AMA collection are separate.

From management:

```bash
dig @10.60.1.4 example.com
dig +tcp @10.60.1.4 example.com
resolvectl status
```

On test:

```bash
sudo unbound-checkconf
sudo systemctl status unbound --no-pager
sudo grep -i unbound /var/log/syslog | tail -20
```

A live run and repeat recap are needed before claiming idempotence for the included DNS role. To roll back, restore the prior fragment, validate the full configuration, and restart Unbound. Management depends on this resolver while it is configured as its DNS server.
