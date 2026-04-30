# 🚀 Ansible Production Playbook Best Practices

> **"In production, reliability is king."**

This document outlines the gold standard for writing Ansible playbooks intended for **production-grade environments**. It covers security, idempotency, debugging logic, and Infrastructure as Code (IaC) principles.

---

## 🛡️ 1. Security & Secrets Management

Never, ever commit secrets to version control. Production stability depends on robust security hygiene.

| ✅ Do | ❌ Don't |
| :--- | :--- |
| Use **Ansible Vault** for passwords, API keys, and certificates. | Hardcode `password=` directly in playbooks or inventory files. |
| Use `--check` mode before every major change to verify safety. | Run commands that modify state without checking first. |
| Separate user accounts from hostvars (don't rely on `ansible_user`). | Assume the current context is always the one you want. |

**Example:**
```yaml
# ❌ NEVER DO THIS
password: "SuperSecretPassword123!"  # Git Commit Risk!

# ✅ DO THIS
password_file: "{{ vault_password }}"
```

---

## 🧱 2. Structure & Organization (IaC Principles)

Production playbooks should be **declarative**, not imperative. Treat the infrastructure definition as code.

### 📁 Directory Structure
```text
project/
├── group_vars/          # Global variables (shared by all roles)
├── host_vars/           # Specific overrides per host
├── playbooks/           # Entry point (.yml)
└── roles/               # Modular, reusable logic
    ├── webserver/       # Self-contained task + vars
    └── database/        # Self-contained task + vars
```

### ⚙️ Playbook Logic
1.  **Order Matters:** Run tasks in logical dependency order (e.g., Install Package -> Configure File -> Restart Service).
2.  **Avoid Giant Plays:** Keep plays under 50 tasks. Split logic into Roles to manage complexity.
3.  **Use `any_errors_fatal`:** Set this carefully. In production, you usually want the playbook to continue despite non-critical errors unless safety depends on it.

---

## ⚙️ 3. Variable Management & Magic Variables

Ansible provides "Magic Variables" (e.g., `ansible_host`, `inventory_hostname`). Using them correctly is crucial for maintainability.

### 🤖 Registration Logic
You must register module outputs to utilize their return values later. **Never assume a module returns a specific variable name.**

```yaml
# ✅ GOOD: Explicit registration and error handling
- name: Install Nginx
  ansible.builtin.packages:
    name: nginx
    state: present
  register: nginx_install_result

- name: Display success if package already installed
  debug:
    msg: "Package installed (or was not needed)"
  when: nginx_install_result.changed is undefined or nginx_install_result.ansible_failed | false
```

### 🧙‍♂️ Magic Variables Safety
*   **`{{ inventory_hostname }}`**: Use for logging which host you are on.
*   **`{{ ansible_host }}`**: Often unreliable in dynamic inventories (e.g., Docker/Ansible Galaxy). Prefer explicit `ip_address`.
*   **`{{ hostvars }}`**: Avoid using `hostvars[hostname]` heavily. It breaks with multi-host logic and slows down rendering.

---

## 🧠 4. Jinja Logic & Efficiency

Templates should be readable, performant, and resilient to missing variables.

### 🚫 Anti-Patterns
```jinja
# ❌ Unsafe: Will fail if the key is missing
data = {{ host_vars[host].database_password }}

# ❌ Inefficient: Using loop for mapping is slow in Jinja 2
{%- for x in data.items() %}...{% endfor -%}
```

### ✅ Production Best Practices
1.  **Use `.default` filter:** Prevent templates from crashing when variables are undefined.
    ```jinja
    {% set version = config.app_version | default('v1.0.0') %}
    ```
2.  **Avoid Loops for Logic:** Use Jinja logic filters instead of `for` loops where possible to keep tasks clean.
3.  **Use `dict_kv` helper:** Access nested dictionaries safely.
4.  **No External Script Calls:** If a task needs complex math, use a Role variable or Ansible module logic (e.g., `ansible.builtin.set_fact`), not external bash scripts unless necessary.

---

## 🐛 5. Debugging & Logging (The Production Approach)

"Debug often" in production doesn't mean "Verbose Mode All Day". It means **instrumentation**.

### 🧩 The Debug Module
Use the `debug` module **only for troubleshooting**. In production, limit this to specific steps where logic is complex.
```yaml
- name: Log a critical state change (Production Safe)
  ansible.builtin.debug:
    msg: "Service {{ service_name }} restarted."
  when: restart_result.changed
```

### 📜 Logging Configuration
Do not rely solely on `ansible.verbose` (-vvv). Configure the Ansible logging system to write logs to a file.
```yaml
# Set default log path via ansible.cfg or group_vars
- name: Set verbose mode only for specific task if needed
  command: "ansible -vvv {{ host }}"
  become_no: true # Example for debug tasks
```

### 🔍 Error Handling Strategy
Production playbooks must handle failure gracefully without crashing the whole job unless it's critical.

```yaml
- name: Attempt to connect (Fail silently)
  ansible.builtin.ping:
    fail_when: false
  register: ping_result

# Log the outcome for audit, but keep playing
- name: Audit connection status
  debug:
    msg: "Ping failed {{ ping_result.failed }}"
```

---

## 🧪 6. Testing & Validation (CI/CD Integration)

Never deploy to production without validation. Use **Molecule** and `check` mode in your CI pipeline.

### ✅ Checklist for Pre-Deploy
1.  **Syntax Check:** Run `ansible-playbook --syntax-check`.
2.  **Dry Run:** Run with `--check --diff` locally and in CI to catch state changes without applying them.
3.  **Idempotency Test:** Run the playbook twice. It must succeed on the second run with zero output (except logs).
4.  **Linting:** Run `ansible-lint`.

```bash
# Example Pre-commit Hook or CI Step
git commit -m "feat: update nginx role" && ansible-lint roles/nginx_role
```

---

## 🚫 7. Anti-Patterns in Production

| Pattern | Why it's bad for Prod | Fix |
| :--- | :--- | :--- |
| **`always_run: true`** on every task (except handlers) | Increases runtime and clutter. | Remove unless necessary. |
| **Global Variables (`group_vars/`) bloat** | Hard to trace specific values per host. | Use `host_vars` or explicit module args. |
| **Using `cmd` without quoting** | Security risks for shell injection. | Quote arguments strictly in `command:`. |
| **Hardcoded `--check-mode` flags** | Makes rollback logic unclear. | Handle `changed` states explicitly. |
| **`debug: msg="..."` in every task** | Clutters logs. | Use a conditional `when` statement. |

---

## 🔒 8. Change Management & Approval Gates

In production, you want to know *why* and *who* ran the playbook before execution.

### 🕵️ Audit Logging
Use `ansible.log` modules (via Ansible Log Handler) or standard stdout redirection for critical changes:
```yaml
- name: Execute Critical Change
  ansible.builtin.command: "systemctl restart apache"
  register: result
  when: request_approval == true # External logic variable
  changed_when: "'restart' in result.stdout"
  tags: [critical, change-mgmt]
```

### 🚦 Deployment Strategy
-   **Blue/Green or Canary:** Use `ansible-galaxy collection install` for versions to track.
-   **Tags:** Use `tags: restart_required` for specific updates that need downtime.

---

## ⚡ Quick Reference Cheat Sheet

| Task | Command/Variable | Note |
| :--- | :--- | :--- |
| **Verbose** | `-vvv` | For debugging, not prod runs. |
| **Vault** | `ansible-vault` | Encrypt passwords at rest. |
| **Dry Run** | `--check` | Verify without changing state. |
| **Diff View** | `--diff` | See what files will change. |
| **Quiet** | `-e` (set vars) | Pass env vars to playbook safely. |

---

> **Final Note:** Always document *why* a task is done. Future you will thank past you for understanding the logic behind the configuration.

📅 **Last Updated:** `{{ ansible_date_time.iso8601_basic }}`  
👤 **Author:** DevOps Engineering Team
