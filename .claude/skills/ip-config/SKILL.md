---
name: ip-config
description: How to author and validate an ip_config.yaml — the single declarative source of truth that makes the whole flow generic across any IP/subsystem. Use when onboarding a new IP or changing an IP's interfaces, clocks, bus, registers, or verification intent.
---

# Authoring `ip_config.yaml`

One file describes an IP; every agent, skill, template, and VIP reads from it. Re-target the entire
flow to a new IP by writing a new `ip_config.yaml` — nothing else is hardcoded.

- **Schema:** [`flow/config/ip_config.schema.json`](../../../flow/config/ip_config.schema.json)
- **Annotated example (the pilot):** [`flow/config/ip_config.example.yaml`](../../../flow/config/ip_config.example.yaml)
- **Validate:** `python flow/scripts/validate_config.py ips/<ip>/ip_config.yaml`

## Required sections

- `ip` — name (module base), version, description, owner.
- `clocks` — one or more; name + frequency. (Pilot is single-clock.)
- `resets` — name, active level, sync style, associated clock.
- `bus` — `protocol` (apb/apb4/axi4-lite/axi4/ahb-lite/wishbone/tilelink-ul), data/addr width,
  clock, reset, role. Drives the VIP choice, PeakRDL `--cpuif`, and RTL port list.
- `registers` — path to the SystemRDL source + `format: systemrdl` (the CSR single source of truth).

## Optional but important

- `interfaces` — non-bus side interfaces; each `kind` (gpio/spi/i2c/uart/axi-stream/custom) maps to a
  VIP agent. Set `has_vip: true` when a reusable agent already exists in `vip/`.
- `interrupts` — sources, level/edge.
- `verification` — `tracks` (single-track `[sv-uvm]`), `coverage_goal_pct`, `primary_simulator` (xsim),
  `regression.{seeds,random_tests}`, and `key_scenarios` (seed the vPlan).
- `traceability` — ID prefixes (`REQ`/`SPEC`/`VP`).

## How each field propagates

| Config | Consumed by |
|---|---|
| `bus.protocol` | VIP bus agent, PeakRDL `--cpuif`, RTL port list, bus-compliance requirements |
| `registers.source` | register-designer → PeakRDL → RTL/RAL/docs |
| `interfaces[]` | tb-architect (which VIP agents to instantiate), requirements, coverage |
| `interrupts[]` | requirements, interrupt covergroups, scoreboard checks |
| `verification.key_scenarios` | requirements + vPlan functional-coverage items |
| `verification.tracks` | which envs tb-architect generates |
| `clocks`/`resets` | RTL clocking/reset, tb clock/reset gen, CDC checks |

## Rules

- Validate before running any stage; a red config blocks the flow.
- Add a new bus/interface `kind` by adding VIP under `vip/` **once** — then any IP can use it via
  config. Don't special-case an IP in an agent or template.
- Keep the config the *only* place IP specifics live; if something feels IP-specific elsewhere, lift
  it into config or a template parameter.
