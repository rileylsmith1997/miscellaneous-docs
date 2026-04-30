# 🎨 Ansible Playbook Best Practices Guide

Welcome! This guide outlines our recommended standards for writing maintainable, secure, and robust Ansible playbooks. Our goal is to create a stable environment where your infrastructure evolves safely over time. 💡

We aim for code that is easy to read, testable, and reliable—treating infrastructure configuration with the same care we apply to application software.

---

## 📝 1. Code Hygiene & Logic

Keeping our logic clean makes troubleshooting easier when things happen in production. It's about writing code that explains *why* it does what it does.

### ⚙️ Register Module Outputs
Module results often contain helpful information (e.g., package names, exit codes). We recommend explicitly **registering** module outputs so you can reference them later in the play or use them to conditionally run tasks. This prevents assuming that a task always returned a value.

```yaml
# ✅ Recommended: Register and check state
- name: Install Apache
  ansible.builtin.packages:
    name: httpd
    state: present
  register: apache_result

# Use the result later if it was actually changed
- name: Display summary
  ansible.builtin.debug:
    msg: "Packages were updated."
  when: apache_result.changed is defined
```

### 🧙‍♂️ Using Magic Variables Safely
Ansible provides many special variables (like `{{ inventory_hostname }}`). These are convenient, but we recommend using them intentionally.

*   **Inventory Hostname:** Use `{{ inventory_hostname }}` for labels and logging when identifying a specific host in a large fleet.
*   **Hostvars:** Avoid accessing `{{ hostvars }}` directly unless necessary. It can become complex with dynamic inventories or parallel execution. When possible, define variables explicitly or use groups.
*   **Contextual Debugging:** When logging output for tracking purposes, combine magic variables with context:

```yaml
- name: Log service restart status
  ansible.builtin.debug:
    msg: "Restarted {{ item }} on {{ inventory_hostname }}"
  loop: "{{ app_services }}"
```

### 🎭 Jinja2 Templates & Logic
Templates should be readable and resilient to undefined data.
*   **Avoid Crashes:** Use the `.default` filter to provide a fallback if a variable is missing. This prevents tasks from failing just because a specific optional variable isn't set.
    ```jinja
    {% set min_memory = required_mem | default("4G") %}
    ```
*   **Logic Over Loops:** Try using Jinja2 filters (like `dict_kv` or `join`) rather than loops to map data, unless looping is necessary for the state change itself.

---

## 🔒 2. Security & Secrets

Handling secrets securely is a shared responsibility across all our infrastructure teams.

*   **Ansible Vault:** For any sensitive data (passwords, API keys, certificates), please use Ansible Vault to encrypt them. This ensures that even if files are read-accessed in Git, the secrets remain protected.
*   **Environment Specificity:** If possible, pass secrets into playbooks via environment variables during execution (`-e`) rather than hardcoding them directly into the `group_vars` or playbook file.
    ```bash
    ansible-playbook site.yml -e "db_password=$(vault_read ...)"
    ```

---

## 🧪 3. Testing & Linting Strategy

Before code reaches production, we run a series of checks to ensure quality. We rely on automated CI/CD components to catch issues early.

### 🔍 Static Analysis & Linting
We utilize our internal CI/CD pipeline to automatically lint playbooks before they are merged. Please ensure your workspaces are compatible with the following tools available in our ecosystem:

*   **Ansible Lint:** This is essential for Ansible YAML files. It detects risky modules and bad practices (like using `command:` instead of `shell`).
*   **PSScriptAnalyzer:** If your playbooks invoke PowerShell scripts or manage Windows environments, we recommend running this to ensure script consistency within the pipeline.
*   **XMLLint:** For any configuration files that rely on XML structures (like certain cloud providers), verify their format using this tool.

**Recommendation:** Configure your local Git hooks or CI workflow to run these tools automatically on every commit. This prevents low-quality changes from entering the repository.

### 🏗️ Validation & Testing
While **Molecule** is a powerful standalone testing framework, we encourage you to leverage our internal CI/CD capabilities for validation. You can configure your pipeline to run idempotency checks (`--check --diff`) alongside syntax validation.

*   **Dry Runs:** Always test with `--check` (or `--dry-run`) in CI before merging.
*   **Syntax Checks:** Run `ansible-playbook --syntax-check` to catch indentation errors early.
*   **Tags:** Use tags extensively. They help you break down a massive deployment into smaller, manageable steps for testing and validation.

```bash
# Example pipeline step for linting
step: run-lint
command: ansible-lint playbooks/site.yml -q --ignore-rules=...
```

---

## 📡 4. Debugging & Logging

We want to be able to troubleshoot issues without needing `ansible-vvvv` running on the production server.

*   **Production Logs:** Instead of relying solely on terminal verbosity, redirect output to logs when debugging specific tasks. This keeps the stdout clean for audit purposes.
*   **Conditional Debugging:** Only use the `debug` module when it adds specific value. For example, use `when: task_changed is true` to keep debug messages relevant only to state changes.
    ```yaml
    - name: Log specific change events
      ansible.builtin.debug:
        msg: "Configuration for {{ item }} updated"
      register: result
      when: result.changed
    ```
*   **Rolling Updates:** Always implement your changes in a rolling fashion (e.g., using Ansible `wait_for` or inventory tags) to ensure you can isolate issues to specific hosts if a change fails.

---

## 🏭 5. Production Environment Best Practices ⚠️

The following practices are strictly applied during the deployment and operation phase of production environments. These are designed to minimize downtime and maximize stability.

### 🛑 Pre-Deployment Checklist
1.  **Verify State Consistency:** Before applying a change, confirm that the target state is defined in code (`--check --diff`) rather than assuming it will work.
2.  **Rollback Strategy:** Every playbook that makes significant changes should be easily reversible. Ensure you have backups or snapshots (e.g., cloud snapshot IDs) available before major updates.
3.  **Tagging for Approval:** Use tags like `prod-rollback` or `prod-monitoring-enabled` to ensure specific infrastructure is ready for a full rollout.

### 🔄 Deployment Strategies
*   **Canary Releases:** When updating playbooks in production, deploy to one host at first. Verify health metrics before moving to the next batch.
    ```yaml
    - name: Deploy to 5% of hosts first (Canary)
      ansible.builtin.command: "deploy_logic.sh"
      tags: canary
      when: item.tags | contains('production') and (item.id in host_group['canary_hosts'])
    ```
*   **Graceful Reboots:** Always prefer `reboot` over `command: shutdown`. If possible, use Ansible modules like `ansible.posix.reboot` which allow for reboot timeouts.

### 📊 Observability & Monitoring
*   **Health Checks:** After running a playbook that modifies services (like Nginx or Apache), ensure your monitoring tool receives a heartbeat. You may need to wait for the service to stabilize before considering it successful.
    ```yaml
    - name: Wait for service health check to pass
      block:
        # Logic to ping endpoint or check status file
        register: health_status
    rescue:
        # Alerting logic on failure
        ansible.builtin.debug:
          msg: "Service did not come back up! Alert Ops."
    ```
*   **Audit Trails:** Keep a record of who made changes and when. Use `ansible.builtin.debug` logs or external audit systems to track playbook execution in production environments.

### 🧹 Post-Deployment Cleanup
*   **Remove Temporary Vars:** If you set temporary facts using `set_fact`, ensure they aren't left lingering if they are no longer needed for the next task run.
*   **Cleanup Files:** When deploying via automation, remove any temporary download files (e.g., `.tar.gz`) immediately after extraction to free up space.

### 🛠️ Error Handling & Fallbacks
*   **Fail Silently on Non-Critical Errors:** If a single host in the inventory fails but shouldn't stop the deployment, use `ignore_errors: true` carefully and ensure it logs the failure so you aren't missing errors.
*   **Use Handlers Wisely:** Handlers run only after tasks change state. Ensure your handlers are atomic (e.g., restart one service at a time) to prevent cascading failures during reboots.

---

**Final Note:** Infrastructure is code, and our code should be as resilient as the systems it manages. If you are unsure about a best practice here, please open an issue or chat with the platform team before proceeding. 🤝
