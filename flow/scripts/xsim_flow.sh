#!/usr/bin/env bash
# =============================================================================
# xsim_flow.sh — generic AMD Vivado xsim driver for the single-track SV/UVM flow.
#
# Compiles, elaborates, and runs a SystemVerilog UVM testbench on Vivado xsim,
# with optional functional + code coverage. IP-agnostic: everything is derived
# from the IP directory layout (ips/<ip>/dv/sv/{filelist.f, tb/<ip>_tb_top.sv}).
#
# Usage:
#   xsim_flow.sh compile <ip_dir>
#   xsim_flow.sh elab    <ip_dir> [--cov]
#   xsim_flow.sh run     <ip_dir> <test> <seed> [--cov] [--covtag <tag>]
#   xsim_flow.sh smoke   <ip_dir> [<test>]            # compile+elab+run (seed 1)
#
# <ip_dir> is the IP root, e.g. ips/pmtpc4 (absolute or relative to repo root).
# Build artifacts (xsim.dir, *.log, *.jou) land in <ip_dir>/dv/sv (git-ignored).
# Per-run coverage snapshots land in <ip_dir>/reports/_cov/<tag>/ for later merge.
#
# Requires Vivado xsim on PATH. If not found, sources $VIVADO_SETTINGS
# (default /tools/Xilinx/2025.1/Vivado/settings64.sh).
# =============================================================================
set -uo pipefail

# ---- locate Vivado -----------------------------------------------------------
if ! command -v xvlog >/dev/null 2>&1; then
    VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/2025.1/Vivado/settings64.sh}"
    if [ -f "$VIVADO_SETTINGS" ]; then
        # shellcheck disable=SC1090
        source "$VIVADO_SETTINGS"
    fi
fi
if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: xvlog not on PATH and \$VIVADO_SETTINGS ($VIVADO_SETTINGS) not found." >&2
    echo "       Install Vivado xsim (see env/README.md) or export VIVADO_SETTINGS." >&2
    exit 127
fi

UVM_LIB="-L uvm"                 # xsim built-in UVM 1.2 (see env/tool-versions.yaml)
TIMESCALE="1ns/1ps"
CC_TYPE="sbct"                   # statement/branch/condition/toggle code coverage

cmd="${1:-}"; ip_dir="${2:-}"
[ -z "$cmd" ] || [ -z "$ip_dir" ] && { echo "usage: xsim_flow.sh <compile|elab|run|smoke> <ip_dir> [...]" >&2; exit 2; }
ip_dir="$(cd "$ip_dir" && pwd)" || { echo "ERROR: ip_dir '$ip_dir' not found" >&2; exit 2; }
ip="$(basename "$ip_dir")"
sv_dir="$ip_dir/dv/sv"
[ -d "$sv_dir" ] || { echo "ERROR: $sv_dir not found" >&2; exit 2; }

# top module = the single tb/*_tb_top.sv basename
top_file="$(ls "$sv_dir"/tb/*_tb_top.sv 2>/dev/null | head -1)"
[ -z "$top_file" ] && { echo "ERROR: no tb/*_tb_top.sv under $sv_dir" >&2; exit 2; }
TOP="$(basename "$top_file" .sv)"
SNAP="${ip}_sim"
COV_ROOT="$ip_dir/reports/_cov"

want_cov=0; covtag=""
shift 2 || true
while [ $# -gt 0 ]; do
    case "$1" in
        --cov) want_cov=1 ;;
        --covtag) shift; covtag="$1" ;;
        *) POS="${POS:-} $1" ;;
    esac
    shift
done

do_compile() {
    cd "$sv_dir"
    rm -rf xsim.dir .Xil ./*.pb 2>/dev/null
    echo ">> [compile] xvlog -sv $UVM_LIB -f filelist.f   ($ip)"
    xvlog -sv $UVM_LIB -f filelist.f
}

do_elab() {
    cd "$sv_dir"
    local covargs=""
    if [ "$want_cov" = 1 ]; then
        covargs="-cc_type $CC_TYPE --cov_db_dir $sv_dir/xsim.cov --cov_db_name ${SNAP}"
        mkdir -p "$sv_dir/xsim.cov"
    fi
    echo ">> [elab] xelab $UVM_LIB -timescale $TIMESCALE $TOP -s $SNAP ${covargs:+(+coverage)}"
    xelab $UVM_LIB -timescale "$TIMESCALE" -relax "$TOP" -s "$SNAP" $covargs
}

do_run() {   # $1=test $2=seed
    local test="$1" seed="$2"
    [ -z "$test" ] && { echo "ERROR: run needs a test name" >&2; exit 2; }
    [ -z "$seed" ] && seed=1
    cd "$sv_dir"
    echo ">> [run] $test seed=$seed ${want_cov:+cov=$want_cov}"
    xsim "$SNAP" -R -testplusarg "UVM_TESTNAME=$test" -sv_seed "$seed"
    local rc=$?
    # snapshot this run's coverage db for later cross-seed merge
    if [ "$want_cov" = 1 ] && [ -d "$sv_dir/xsim.cov" ]; then
        local tag="${covtag:-${test}_seed${seed}}"
        rm -rf "$COV_ROOT/$tag"; mkdir -p "$COV_ROOT/$tag"
        cp -r "$sv_dir/xsim.cov/." "$COV_ROOT/$tag/" 2>/dev/null
    fi
    return $rc
}

case "$cmd" in
    compile) do_compile ;;
    elab)    do_elab ;;
    run)     set -- $POS; do_run "${1:-}" "${2:-1}" ;;
    smoke)
        set -- $POS; test="${1:-${ip}_sanity_test}"
        do_compile && do_elab && do_run "$test" 1 ;;
    *) echo "unknown subcommand: $cmd" >&2; exit 2 ;;
esac
