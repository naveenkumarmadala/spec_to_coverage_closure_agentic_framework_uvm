---
description: Generate the requirements database and the design specification for an IP from its ip_config and any raw spec material.
argument-hint: <ip_name>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch
---

Produce the front-end specification for IP `$1`.

1. Load and validate `ips/$1/ip_config.yaml`.
2. Delegate to the **requirements-analyst** agent (using the **spec-to-requirements** skill) to
   create `ips/$1/spec/requirements.md` — atomic, testable, ID'd requirements. Include derived
   requirements from the config and an Open Questions section.
3. Then delegate to the **design-architect** agent to create `ips/$1/spec/design_spec.md`, with each
   spec item tracing to REQ IDs.
4. Report a summary: # requirements by category, # spec items, and any Open Questions that block
   progress. If Open Questions exist, surface them to the user before continuing to registers.
