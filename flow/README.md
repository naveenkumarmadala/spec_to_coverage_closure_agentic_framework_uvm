# flow/ — the generation engine

Turns an `ip_config.yaml` into concrete artifacts and drives the free toolchain.

| Dir | Purpose | Status |
|---|---|---|
| `config/` | `ip_config` JSON schema + annotated example + validator | **P0 (done)** |
| `templates/` | Jinja templates for the SystemVerilog UVM env, testbench, filelists | P3 |
| `scripts/` | Runners: config validation, xsim compile/elab/run, seeded regression, coverage merge | P0→P5 |

Everything here is IP-agnostic: it reads config + templates, never hardcodes an IP.

## Available now (all IP-agnostic — take `ips/<ip>`)

- `scripts/validate_config.py <ip_config.yaml>` — schema + cross-field validation.
- `scripts/doc_to_text.py <file.docx|.md|.txt>` — front-door: convert a Word/MD requirement doc to
  markdown (tables preserved; stdlib, no deps). PDFs are read by the spec-ingestor directly.
- `scripts/xsim_flow.sh <compile|elab|run|smoke> <ip_dir> [...]` — the xsim driver (built-in UVM,
  optional coverage). Honors `$VIVADO_SETTINGS` (default `/tools/Xilinx/2025.1/Vivado/settings64.sh`).
- `scripts/run_regression.py <ip_dir>` — seed sweep over all discovered tests; emits the union
  functional report + a **DUT-scoped** code report (applies the IP's exclusion file).
- `scripts/gen_exclusions.py <ip_dir>` — derive the DUT-scoping code-coverage exclusion file from the
  IP's filelist (waives VIP/tests/RAL/TB/UVM; keeps DUT RTL).
- `scripts/gen_testplan.py <ip_dir>` — render the traditional Excel test plan from vplan + requirements
  (Test Plan / Requirements Traceability / data-driven Coverage Summary).
- `scripts/coverage_report.py <ip_dir>` — roll coverage up the bin→vPlan→REQ spine into
  `reports/coverage_summary.md` (per-vPlan + per-REQ tables, numbers read from real reports).

Later phases add: `run_peakrdl.py`, `gen_env.py` (template-driven env generation — renders
`flow/templates/` per the hybrid model in `uvm-env-scaffold`).
