# flow/tools/ — uniform toolchain wrappers (P2)

Thin Python wrappers giving every backend tool a consistent CLI, return-code, and log convention so
agents/scripts don't special-case tool quirks.

Planned: `run_verible.py` (lint/format), `run_verilator.py` (lint / build / sim / coverage),
`run_icarus.py` (cross-check), `run_yosys.py` (elaboration), `run_peakrdl.py` (RTL/RAL/docs/headers),
`run_sv2v.py`. Each reads `ip_config.yaml` for defaults and writes logs under the IP's `reports/`.
