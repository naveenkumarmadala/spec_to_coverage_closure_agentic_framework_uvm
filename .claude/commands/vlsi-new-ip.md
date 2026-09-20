---
description: MANUAL/ADVANCED path — scaffold a new IP working area with a hand-authored ip_config.yaml. Prefer /vlsi-ingest <spec-file> to auto-extract the config from a requirement document.
argument-hint: <ip_name> [one-line description]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

> **Prefer `/vlsi-ingest <spec-file>`** — the normal front door extracts the config from a
> requirement document automatically. Use this manual path only when you have no spec document and
> want to hand-author the config.

Onboard a new IP named `$1` into the flow.

1. Create `ips/$1/` with subdirs `spec/ rdl/ rtl/ dv/sv vplan/ reports/`.
2. Copy `flow/config/ip_config.example.yaml` to `ips/$1/ip_config.yaml` and adapt it: set
   `ip.name: $1`, a sensible description from "$ARGUMENTS", and leave clocks/resets/bus/registers/
   interfaces as sensible defaults for the user to edit. Use the **ip-config** skill for field
   meanings.
3. Validate it: `python flow/scripts/validate_config.py ips/$1/ip_config.yaml`.
4. Print a short next-steps checklist: fill in the bus/interfaces/registers, then run `/vlsi-spec $1`.

Do not invent detailed IP behavior — set up the skeleton and config, and ask the user for the
specifics you need (bus protocol, interfaces, register intent) if "$ARGUMENTS" doesn't provide them.
