# Massdriver Skills for Claude Code

Build infrastructure bundles for [Massdriver](https://massdriver.cloud), the internal developer platform that turns infrastructure-as-code into reusable, self-service components with built-in guardrails.

## Installation

```bash
/plugin marketplace add massdriver-cloud/massdriver-skill
```

## What This Skill Does

This skill helps platform engineers create Massdriver bundles—reusable IaC modules that package Terraform, OpenTofu, or Helm with input schemas, artifact contracts, and operational policies. Bundles enable developer self-service while encoding your organization's security, compliance, and best practices.

**Capabilities:**
- Guides bundle development with proper lifecycle scoping
- Enforces critical rules (namespace collisions, artifact matching, generated files)
- Provides patterns for connections, artifacts, alarms, and Checkov compliance
- Includes copy-paste snippets for common bundle files

## When It Activates

The skill auto-activates when:
- Working in `bundles/`, `artifact-definitions/`, or `platforms/` directories
- Editing `massdriver.yaml` files
- Asking about bundles, artifacts, connections, or Massdriver patterns

## Plugin Contents

```
massdriver-skill/
├── .claude-plugin/
│   └── marketplace.json
└── massdriver/
    ├── .claude-plugin/
    │   └── plugin.json
    └── skills/
        └── massdriver/
            ├── SKILL.md              # Core instructions
            ├── PATTERNS.md           # Complete bundle and artifact examples
            ├── references/
            │   ├── alarms.md         # AWS/GCP/Azure monitoring setup
            │   └── compliance.md     # Checkov remediation workflow
            └── snippets/
                ├── massdriver-yaml.yaml    # Bundle config template
                ├── artifacts-tf.tf.example # Artifact resource template
                └── operator-md.md          # Runbook template
```

## Requirements

- [Massdriver CLI](https://docs.massdriver.cloud/cli/overview) (`mass`)
- OpenTofu or Terraform

## Learn More

- [Massdriver Documentation](https://docs.massdriver.cloud/)
- [Bundle Development Guide](https://docs.massdriver.cloud/bundles)
- [Open Source Bundles](https://github.com/massdriver-cloud/aws-rds-postgres) (examples)

## License

Apache 2.0 - See [LICENSE](LICENSE)
