# Reporting a Vulnerability

> ⚠️  **Do not open a public issue for security vulnerabilities.**

Please email security issues to `security@contribsys.com` or use GitHub's **“Report a vulnerability”** feature.

# Vulnerability Management

## Scope

This policy applies to:

- Sidekiq’s source code and configuration files.
- Ruby dependencies declared in `sidekiq.gemspec`.
- Continuous Integration (CI) pipelines and deployment scripts.
- Any related documentation or infrastructure as code in this repository.

---

## Acknowledgment and Response Time

- **Initial acknowledgment:** within **48 hours**.
- **Triage and validation:** within **7 days**.
- **Fix release target:** within **14 days** of validation, depending on severity.

---

## Assessment and Classification

| Level | Description | Example |
|--------|--------------|----------|
| **Critical** | Remote code execution, data exfiltration, or supply-chain compromise | Unsafe YAML deserialization |
| **High** | Privilege escalation or significant data exposure | SQL injection, open redirect |
| **Medium** | Limited impact or mitigated by configuration | Denial of Service from malformed input |
| **Low** | Minor issue or best practice improvement | Information disclosure via logs |

Severity is determined using the **CVSS v3.1** scoring system.

---

## Release Management

- Security patches are published as a **patch release** (e.g., `v1.2.3`).
- Release notes must include a **Security** section containing:
  - Description of the issue.
  - CVE identifier (if applicable).
  - Affected and fixed versions.
  - Credits to the reporter (if they consent).

## Dependency Management

- Use **Bundler Audit** and **Dependabot** for automated CVE scanning.
- Review all Gem updates for security implications.
- Monitor **RubySec Advisory Database** and **CVE feeds** for new issues.

---

## Communication

- Users are notified of security fixes via GitHub Security Advisories.
- Public disclosure occurs **only after** the patch is released and verified.

---

## Continuous Monitoring and Improvement

- Automated scans (`bundle audit`, `brakeman`) run in CI pipelines.
- Annual review of this policy or after any major incident.

---

## References

- [RubySec Advisory Database](https://github.com/rubysec/ruby-advisory-db)
- [OWASP Vulnerability Management Guide](https://owasp.org/www-project-vulnerability-management/)
- [GitHub Security Advisories](https://docs.github.com/en/code-security/security-advisories)
- [CVSS v3.1 Specification](https://www.first.org/cvss/specification-document)
