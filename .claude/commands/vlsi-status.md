---
description: Show the lifecycle status of an IP (or all IPs) — which stages/artifacts exist, gate status, and coverage — plus what to run next.
argument-hint: [ip_name]
allowed-tools: Read, Bash, Grep, Glob
---

Report front-end lifecycle status.

If `$1` is given, report for that IP; otherwise scan `ips/*/` and report all.

For each IP, check for and summarize:
- `ip_config.yaml` (valid?), `spec/requirements.md`, `spec/design_spec.md`
- `rdl/*.rdl` + `rdl/generated/` (PeakRDL outputs present?)
- `rtl/*.sv` and whether the static gate passed (from `reports/`)
- `vplan/vplan.yaml`, `dv/sv/` (UVM env present? smoke passing on xsim?)
- latest `reports/coverage_summary.md` (overall %, per-REQ closure)

Present a compact table: IP | spec | regs | rtl | gate | env | tests | coverage. Then state the
single **next recommended command** for each IP (e.g. `/vlsi-registers apb_gpio`). Read-only — do
not modify anything.
