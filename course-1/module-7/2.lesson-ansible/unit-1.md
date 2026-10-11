---
kind: unit
title: "Lesson 14 — Node Operations with Ansible"
name: 2-lesson-ansible-unit-1
---

# Lesson 14 — Node Operations with Ansible

> **Tier:** 3 — Full 5-VM lab  
> **VMs:** All 5 (bootstrap as control node, vm2–vm5 as managed nodes)  
> **Objective:** Use Ansible from the bootstrap VM to configure, inspect, and
> operate NKP cluster nodes — the same way platform teams manage nodes in
> production Nutanix environments.

---

## Why Ansible with NKP?

NKP provisions nodes automatically via Cluster API, but **day-2 operations**
still require direct node access:

- Pre-flight checks before `nkp create cluster`
- Kernel tuning (`sysctl`, `ulimits`, huge pages)
- Rotating credentials or certificates across all nodes
- Installing node-level monitoring agents
- Debugging and remediating failed nodes
- Draining and cordoning nodes for maintenance

Ansible is the standard tool for this in production NKP environments. The `nkp`
CLI provisions the cluster; Ansible operates the underlying OS.

---

## Lab topology

```
vm1 (bootstrap) ──ansible──▶ vm2 (controlplane)  172.16.0.11
                         ──▶ vm3 (worker-01)      172.16.0.12
                         ──▶ vm4 (worker-02)      172.16.0.13
                         ──▶ vm5 (worker-03)      172.16.0.14
```

Ansible runs on **vm1** (the bootstrap / operator workstation). It connects to
vm2–vm5 over SSH using the shared lab network (`172.16.0.0/24`).

---

## Part 1 — Install Ansible on vm1

```bash
# On vm1 (bootstrap)
pip3 install --user ansible
ansible --version
```

Expected output:
```
ansible [core 2.17.x]
  python version = 3.12.x
```

---

## Part 2 — Set up SSH access

NKP nodes in the lab use a pre-configured `laborant` user. Set up SSH key auth
so Ansible can connect without a password:

```bash
# Generate a key pair on vm1 (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/nkp_lab -N ""

# Copy the public key to each node
for ip in 172.16.0.11 172.16.0.12 172.16.0.13 172.16.0.14; do
    ssh-copy-id -i ~/.ssh/nkp_lab.pub laborant@${ip}
done

# Test connectivity
ssh -i ~/.ssh/nkp_lab laborant@172.16.0.11 hostname
```

---

## Part 3 — Create the inventory

```bash
mkdir -p ~/ansible-nkp
cat > ~/ansible-nkp/inventory.ini << 'EOF'
[controlplane]
vm2 ansible_host=172.16.0.11

[workers]
vm3 ansible_host=172.16.0.12
vm4 ansible_host=172.16.0.13
vm5 ansible_host=172.16.0.14

[nkp_nodes:children]
controlplane
workers

[nkp_nodes:vars]
ansible_user=laborant
ansible_ssh_private_key_file=~/.ssh/nkp_lab
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
```

Test the inventory:

```bash
cd ~/ansible-nkp
ansible nkp_nodes -i inventory.ini -m ping
```

Expected:
```
vm2 | SUCCESS => {"ping": "pong"}
vm3 | SUCCESS => {"ping": "pong"}
vm4 | SUCCESS => {"ping": "pong"}
vm5 | SUCCESS => {"ping": "pong"}
```

---

## Part 4 — Ad-hoc commands

Run commands across all nodes without a playbook:

```bash
# Check OS version on all nodes
ansible nkp_nodes -i inventory.ini -m command -a "cat /etc/rocky-release"

# Check RKE2 service status
ansible nkp_nodes -i inventory.ini -m command -a "systemctl status rke2-server rke2-agent" --become

# Check disk usage
ansible nkp_nodes -i inventory.ini -m command -a "df -h /"

# Check kernel version
ansible nkp_nodes -i inventory.ini -m command -a "uname -r"

# Check available memory
ansible nkp_nodes -i inventory.ini -m command -a "free -h"
```

---

## Part 5 — Pre-flight playbook

This is the playbook NKP platform teams run **before** `nkp create cluster` to
ensure nodes meet NKP requirements.

```bash
cat > ~/ansible-nkp/preflight.yaml << 'EOF'
---
- name: NKP node pre-flight checks
  hosts: nkp_nodes
  become: true

  tasks:

    - name: Check OS is Rocky Linux 9
      assert:
        that: ansible_distribution == "Rocky" and ansible_distribution_major_version == "9"
        fail_msg: "Node {{ inventory_hostname }} is not Rocky Linux 9"
        success_msg: "✓ OS: {{ ansible_distribution }} {{ ansible_distribution_version }}"

    - name: Check minimum RAM (8 GB)
      assert:
        that: ansible_memtotal_mb >= 7800
        fail_msg: "Node {{ inventory_hostname }} has only {{ ansible_memtotal_mb }} MB RAM (need 8 GB)"
        success_msg: "✓ RAM: {{ (ansible_memtotal_mb / 1024) | round(1) }} GB"

    - name: Check minimum CPUs (4)
      assert:
        that: ansible_processor_vcpus >= 4
        fail_msg: "Node {{ inventory_hostname }} has only {{ ansible_processor_vcpus }} vCPUs (need 4)"
        success_msg: "✓ vCPUs: {{ ansible_processor_vcpus }}"

    - name: Check iscsid is enabled
      stat:
        path: /etc/systemd/system/multi-user.target.wants/iscsid.service
      register: iscsi_symlink

    - name: Assert iscsid is enabled
      assert:
        that: iscsi_symlink.stat.exists
        fail_msg: "iscsid not enabled on {{ inventory_hostname }}"
        success_msg: "✓ iscsid enabled"

    - name: Check RKE2 binary exists
      stat:
        path: /usr/local/bin/rke2
      register: rke2_bin

    - name: Assert RKE2 is installed
      assert:
        that: rke2_bin.stat.exists
        fail_msg: "RKE2 not found on {{ inventory_hostname }}"
        success_msg: "✓ RKE2 installed"
EOF
```

Run it:

```bash
ansible-playbook -i inventory.ini preflight.yaml
```

---

## Part 6 — Kernel tuning playbook

NKP requires specific kernel settings for networking and container workloads:

```bash
cat > ~/ansible-nkp/kernel-tuning.yaml << 'EOF'
---
- name: Apply NKP kernel tuning
  hosts: nkp_nodes
  become: true

  tasks:

    - name: Set kernel parameters for NKP
      sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        state: present
        sysctl_file: /etc/sysctl.d/99-nkp.conf
        reload: true
      loop:
        - { key: "net.bridge.bridge-nf-call-iptables",  value: "1" }
        - { key: "net.bridge.bridge-nf-call-ip6tables", value: "1" }
        - { key: "net.ipv4.ip_forward",                 value: "1" }
        - { key: "net.ipv6.conf.all.forwarding",        value: "1" }
        - { key: "fs.inotify.max_user_watches",         value: "524288" }
        - { key: "fs.inotify.max_user_instances",       value: "512" }
        - { key: "vm.max_map_count",                    value: "262144" }

    - name: Disable swap
      command: swapoff -a
      when: ansible_swaptotal_mb > 0

    - name: Remove swap from fstab
      replace:
        path: /etc/fstab
        regexp: '^([^#].*\sswap\s.*)$'
        replace: '# \1'
EOF
```

Run it:

```bash
ansible-playbook -i inventory.ini kernel-tuning.yaml
```

---

## Part 7 — Node drain and cordon

In production NKP, node maintenance uses `kubectl` drain before Ansible work:

```bash
# On vm1, drain a worker node before maintenance
kubectl drain vm3 --ignore-daemonsets --delete-emptydir-data

# Run your Ansible maintenance playbook
ansible-playbook -i inventory.ini kernel-tuning.yaml --limit vm3

# Uncordon the node when done
kubectl uncordon vm3

# Verify it's back
kubectl get nodes
```

---

## Part 8 — Rolling restart of RKE2

Sometimes you need to restart RKE2 across all nodes in a controlled sequence:

```bash
cat > ~/ansible-nkp/rolling-restart.yaml << 'EOF'
---
- name: Rolling restart of RKE2 — control plane first
  hosts: controlplane
  become: true
  serial: 1

  tasks:
    - name: Restart rke2-server
      systemd:
        name: rke2-server
        state: restarted
      async: 60
      poll: 5

- name: Rolling restart of RKE2 — workers one at a time
  hosts: workers
  become: true
  serial: 1

  tasks:
    - name: Restart rke2-agent
      systemd:
        name: rke2-agent
        state: restarted
      async: 60
      poll: 5
EOF
```

```bash
ansible-playbook -i inventory.ini rolling-restart.yaml
```

---

## What you learned

| Concept | Command |
|---|---|
| Ansible inventory | `inventory.ini` with groups and vars |
| Ad-hoc commands | `ansible nkp_nodes -m command -a "..."` |
| Pre-flight assertions | `assert` module with facts |
| Kernel tuning | `sysctl` module |
| Rolling operations | `serial: 1` in playbooks |
| Drain + maintenance | `kubectl drain` → Ansible → `kubectl uncordon` |

---

## Real NKP connection

In a real NKP on AHV deployment, Ansible is used for:

- **Pre-flight** before `nkp create cluster` (Nutanix quickstart scripts do this)
- **Node remediation** when CAPI marks a node unhealthy
- **Compliance scanning** (CIS benchmark checks on the Rocky 9.7 CIS-hardened image)
- **Secret rotation** across the node fleet

The `nkp-quickstart` repo at [github.com/nutanixdev/nkp-quickstart](https://github.com/nutanixdev/nkp-quickstart)
includes an `nkp-env` script that sets the environment variables Ansible needs
to connect to Nutanix AHV nodes.

---

## Next steps

➡️ [Back to course index](../../index.md)
