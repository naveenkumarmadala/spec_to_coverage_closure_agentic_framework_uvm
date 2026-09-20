---
name: vip-registry
description: How the pluggable VIP registry makes the flow protocol-agnostic — selecting an existing bus/interface VIP, and adding a plug-in for a brand-new protocol (registry entry + VIP skeleton) with no agent or schema edits. Use when a config references a protocol/interface, or when onboarding an unknown one.
---

# The pluggable VIP registry

`flow/config/vip_registry.yaml` is the single authority for which bus protocols and interface kinds
exist. `ip_config.yaml` values (`bus.protocol`, `interfaces[].kind`) are validated against it — there
is **no fixed protocol list in the schema or the agents**. This is what makes the flow work
"irrespective of any protocol."

## Selecting a VIP (the common case)
- The validator resolves `bus.protocol` → `buses.<name>` and each `interfaces[].kind` →
  `interfaces.<name>`. The entry gives the VIP `path` (under `vip/`) and — for a bus — the PeakRDL
  `cpuif` name.
- `status: ready` → the VIP is usable now. `planned` → registered but not yet built (the flow will
  scaffold/flag it). `stub` → auto-created for an unknown protocol; needs a real VIP.

## Adding a brand-new protocol (the plug-in path)
No agent/skill/schema changes are needed — just two steps:

1. **Register it** — add an entry under `buses:` (or `interfaces:`) in `vip_registry.yaml`:
   ```yaml
   buses:
     my_bus:
       display_name: "My Custom Bus"
       path: vip/my_bus
       cpuif: passthrough        # or a PeakRDL cpuif if PeakRDL supports it; else custom glue
       status: planned
   ```
2. **Provide the VIP** — create `vip/my_bus/sv/` with the reusable UVM agent (driver, monitor,
   sequencer, seq_item, coverage), plus a reg-adapter so the RAL can drive it. Follow the
   `uvm-env-scaffold` reuse boundary: the bus machinery lives here, never in an IP's `dv/`.

After that, any `ip_config.yaml` can set `bus.protocol: my_bus` and the whole flow uses it.

## Custom / escape-hatch VIP
For a one-off, set `bus.vip` (or `interfaces[].vip`) in the config to a VIP path directly — the
validator accepts a `vip` override even if the `protocol`/`kind` isn't a registry key. Prefer
registering it properly when it'll be reused.

## PeakRDL cpuif mapping
For a register bus, `cpuif` tells `register-designer` which `peakrdl regblock --cpuif` to use. If
PeakRDL has no matching cpuif, use `passthrough` and add a thin adapter from the bus VIP to the
regblock's native interface.

## Rules
- One protocol = one registry entry + one VIP dir. Never special-case a protocol inside an agent,
  skill, or template.
- Flag `stub`/`planned` protocols clearly at the ingestion gate so the user knows a VIP must be built.
