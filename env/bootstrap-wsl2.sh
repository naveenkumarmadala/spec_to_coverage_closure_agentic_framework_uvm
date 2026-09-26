#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-wsl2.sh — install the free VLSI front-end toolchain on WSL2 Ubuntu.
#
# Single-track SystemVerilog UVM flow: the UVM simulator is AMD Vivado xsim,
# which is a MANUAL install (see env/README.md) and is NOT installed here — this
# script installs everything else and then checks that xsim is reachable.
#
# Installs: Verible (lint) and a Python venv (env/.venv) with PeakRDL for register
# generation and the flow scripts. Everything else — elaboration, synthesizability
# (static gate), simulation, coverage — runs on Vivado (xvlog/xelab/xsim/xcrg and
# vivado synth_design). NO cocotb / pyuvm / Verilator / Yosys / sv2v / Icarus.
#
# Usage (from a WSL2 Ubuntu shell, repo root or env/ dir):
#     bash env/bootstrap-wsl2.sh            # full install
#     bash env/bootstrap-wsl2.sh --check    # only verify what's installed
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
TOOLS_DIR="$HERE/_tools"          # git-ignored local tool downloads
VENV_DIR="$HERE/.venv"
VERIBLE_TAG="${VERIBLE_TAG:-v0.0-3946-g851d3ff4}"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/2025.1/Vivado/settings64.sh}"

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

check_versions() {
  log "Static tool versions:"
  for t in verible-verilog-lint python3; do
    if have "$t"; then printf '  %-22s %s\n' "$t" "$("$t" --version 2>&1 | head -1)";
    else printf '  %-22s \033[1;31mMISSING\033[0m\n' "$t"; fi
  done
  log "UVM simulator (Vivado xsim — manual install):"
  if ! have xvlog && [ -f "$VIVADO_SETTINGS" ]; then source "$VIVADO_SETTINGS" || true; fi
  if have xvlog; then printf '  %-22s %s\n' "xvlog/xsim" "$(xsim --version 2>&1 | head -1)";
  else printf '  %-22s \033[1;31mMISSING\033[0m (install Vivado ML Standard; see env/README.md)\n' "xsim"; fi
  if have vivado; then printf '  %-22s %s\n' "vivado (synth gate)" "$(vivado -version 2>&1 | head -1)";
  else printf '  %-22s \033[1;31mMISSING\033[0m (same Vivado install)\n' "vivado"; fi
  if [[ -d "$VENV_DIR" ]]; then
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    printf '  %-22s %s\n' "py:peakrdl" "$(python3 -c "import importlib.metadata as m; print(m.version('peakrdl'))" 2>/dev/null || echo MISSING)"
    deactivate || true
  else
    warn "Python venv not found at $VENV_DIR"
  fi
}

if [[ "${1:-}" == "--check" ]]; then check_versions; exit 0; fi

# --- 0. sanity -------------------------------------------------------------
if ! grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
  warn "This does not look like WSL2. Continuing, but this script targets Ubuntu on WSL2."
fi
mkdir -p "$TOOLS_DIR"

# --- 1. system packages ----------------------------------------------------
log "Installing apt dependencies (sudo may prompt)…"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  git make g++ python3 python3-pip python3-venv \
  gtkwave wget curl unzip ca-certificates

# --- 2. Verible (prebuilt release) -----------------------------------------
if ! have verible-verilog-lint; then
  log "Fetching Verible $VERIBLE_TAG…"
  VB_URL="https://github.com/chipsalliance/verible/releases/download/${VERIBLE_TAG}/verible-${VERIBLE_TAG}-linux-static-x86_64.tar.gz"
  if wget -q "$VB_URL" -O "$TOOLS_DIR/verible.tar.gz"; then
    tar -xzf "$TOOLS_DIR/verible.tar.gz" -C "$TOOLS_DIR"
    sudo cp "$TOOLS_DIR"/verible-*/bin/* /usr/local/bin/
  else
    warn "Could not download Verible ($VB_URL). Update VERIBLE_TAG to a current release and re-run."
  fi
fi

# --- 3. Python venv: PeakRDL + flow scripting (NO cocotb/pyuvm) ------------
log "Creating Python venv at $VENV_DIR…"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python3 -m pip install --quiet --upgrade pip wheel
python3 -m pip install --quiet \
  "peakrdl>=1.1" "peakrdl-regblock>=1.1" "peakrdl-uvm>=2.2" \
  "peakrdl-html>=2.10" "peakrdl-cheader>=1.0" "systemrdl-compiler>=1.27" \
  "jinja2>=3.1" "pyyaml>=6.0" "jsonschema>=4.0" "openpyxl>=3.1"
deactivate

# --- 4. Vivado reminder ----------------------------------------------
if ! ( have xvlog || { [ -f "$VIVADO_SETTINGS" ] && source "$VIVADO_SETTINGS" && have xvlog; } ); then
  warn "Vivado xsim not found. It is the UVM simulator for this flow and must be installed"
  warn "manually (free 'Vivado ML Standard', Linux, into WSL2). See env/README.md."
fi

log "Done. Activate the Python env with:  source env/.venv/bin/activate"
log "Verify the install with:            bash env/bootstrap-wsl2.sh --check"
check_versions
