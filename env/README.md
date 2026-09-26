# Environment setup

*New to this project entirely — no WSL2, no Claude Code yet? [`../GETTING_STARTED.md`](../GETTING_STARTED.md)
covers all of that from scratch; this page is the reference for what the bootstrap script does.*

The flow is **single-track SystemVerilog UVM** run on **AMD Vivado xsim**, under **WSL2 Ubuntu**.
Everything except Vivado is installed by the bootstrap; **Vivado is a manual install** (below).

## 1. WSL2 + Verible + the Python venv

From Windows PowerShell, install WSL2 + Ubuntu once:

```powershell
wsl --install -d Ubuntu-24.04
```

Then, inside the Ubuntu shell, from the repo root:

```bash
bash env/bootstrap-wsl2.sh          # Verible + PeakRDL venv (everything else is Vivado)
source env/.venv/bin/activate       # activate the Python (PeakRDL + flow scripting) env
bash env/bootstrap-wsl2.sh --check  # verify versions (incl. whether xsim is reachable)
```

> Access this repo from WSL at `/mnt/d/mnk/spec_to_cpqc_agent/claude_uvm_exp_sep_09`. For faster
> simulation I/O you can clone into the Linux filesystem (e.g. `~/vlsi-frontend`) instead of `/mnt/d`.

## 2. Vivado xsim — the UVM simulator (manual install)

xsim runs the complete UVM environment (native constrained randomization, functional + code
coverage, SVA). Install the **free** edition, for **Linux, inside WSL2**:

```bash
sudo apt update && sudo apt install -y libtinfo5 libncurses5 libx11-6 libxrender1 libxtst6 libxi6 default-jre
```

1. Sign in to an AMD account and download the **"AMD Unified Installer for FPGAs & Adaptive SoCs —
   Linux Self Extracting Web Installer"** (2024.1 or newer). Copy it into WSL.
2. Run it and choose edition **"Vivado ML Standard"** (free, no license file). Install to `/tools/Xilinx`
   (needs ~50 GB free on the WSL2 disk — put the WSL distro on a drive with real space).
3. Put the tools on PATH (add to `~/.bashrc`), then verify:

```bash
source /tools/Xilinx/2025.1/Vivado/settings64.sh
xvlog --version && xsim --version
```

The flow scripts source `$VIVADO_SETTINGS` (default `/tools/Xilinx/2025.1/Vivado/settings64.sh`) when
`xvlog` isn't already on PATH — export `VIVADO_SETTINGS` if your install path differs.

xsim ships a precompiled **UVM 1.2** (used via `-L uvm`), so no separate UVM build is needed to start.
The Accellera UVM sources under `env/_tools/uvm-core/` are bundled for compiling UVM 2017/2020 when an
IP requests it (`verification.uvm_version`).

## 3. Running

```bash
bash flow/scripts/xsim_flow.sh smoke ips/<ip> <ip>_sanity_test   # one test end-to-end
python3 flow/scripts/run_regression.py ips/<ip>                  # seeded regression + coverage
```

## What gets installed (by bootstrap)

Pinned in [`tool-versions.yaml`](tool-versions.yaml): **Verible** (lint/format/syntax) and a Python venv with the **PeakRDL** exporters (regblock RTL, UVM
RAL, HTML docs, C headers) plus the flow's scripting deps. No cocotb/pyuvm — the Python verification
track has been retired.

## Docker (static/generation toolchain only)

[`Dockerfile`](Dockerfile) provides Verible and PeakRDL for lint and register generation. It does
**not** contain Vivado (license + size), which runs the static gate's elaboration and synthesis, UVM
simulation and coverage; run those in a WSL2/host environment where Vivado is installed.
