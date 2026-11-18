# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| 0.2.x   | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in this Helm chart, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email [contact@corveil.com](mailto:contact@corveil.com) with:

- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Response Timeline

- **Acknowledgment**: Within 2 business days
- **Initial Assessment**: Within 5 business days
- **Fix Release**: Depending on severity, typically within 14 days for critical issues

## Scope

This policy covers the Helm chart templates, default configurations, and documentation in this repository. For vulnerabilities in the Corveil application itself, please report to the [Corveil repository](https://github.com/corveil/corveil).

## Best Practices

When deploying Corveil, we recommend:

- Always set a strong `corveil.secretKey` (use `openssl rand -hex 32`)
- Run production with `corveil.environment=production` and `corveil.devAuth=false` (dev login is evaluation-only)
- Give the database the three Corveil roles (`corveil_app`, `corveil_system`, owner) so row-level security isolates organizations
- Use `existingSecret` with a secrets manager (Vault, Sealed Secrets, ESO) for sensitive values
- Enable network policies in production clusters
- Use TLS termination via Ingress or Istio
- Regularly update to the latest chart version
