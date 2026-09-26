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
#   xsim_flow.sh elab    <ip_dir> [--cov] [--toggle]
#   xsim_flow.sh run     <ip_dir> <test> <seed> [--cov] [--toggle] [--covtag <tag>] [--plusargs "+A +B"]
#   xsim_flow.sh smoke   <ip_dir> [<test>]            # compile+elab+run (seed 1)
#   xsim_flow.sh wave    <ip_dir> <test> [<seed>]     # compile+elab+run with a waveform
#
# --toggle selects the CODE-TOGGLE measurement snapshot (<ip>_tcov): the testbench top
# ONLY, without the bind top (tb/<ip>_binds.sv): on xsim a bound checker makes the DUT nets
# it observes lose their toggle coverage. Assertions / functional / stmt / branch / cond come
# from the normal <ip>_sim snapshot (tb top + bind top).
#
# `wave` builds a third snapshot, <ip>_wave (tb top + bind top, `-debug typical`, no
# coverage), runs the test with every signal under the tb top logged, and writes
# <ip_dir>/reports/waves/<test>_seed<seed>.wdb — Vivado's native waveform database, opened
# with `xsim --gui <file>.wdb` (or File > Open Waveform Database in Vivado). No $dumpvars/VCD
# is used anywhere: its mere presence in a design stops xsim code-toggle recording.
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
# optional extra top, elaborated in the normal and wave snapshots (never in the code-toggle one):
#   tb/<ip>_binds.sv -> module <ip>_binds : white-box SVA/coverage binds
EXTRA_TOPS=""
[ -f "$sv_dir/tb/${ip}_binds.sv" ] && EXTRA_TOPS="$EXTRA_TOPS ${ip}_binds"
COV_ROOT="$ip_dir/reports/_cov"
WAVE_ROOT="$ip_dir/reports/waves"

want_cov=0; covtag=""; toggle=0; plusargs=""; wave=0
[ "$cmd" = wave ] && wave=1
shift 2 || true
while [ $# -gt 0 ]; do
    case "$1" in
        --cov) want_cov=1 ;;
        --toggle) toggle=1 ;;
        --covtag) shift; covtag="$1" ;;
        --plusargs) shift; plusargs="$1" ;;
        *) POS="${POS:-} $1" ;;
    esac
    shift
done
if [ "$wave" = 1 ]; then
    SNAP="${ip}_wave"; TOPS="$TOP$EXTRA_TOPS"; want_cov=0   # waveform build: debug info, no coverage
elif [ "$toggle" = 1 ]; then
    SNAP="${ip}_tcov"; TOPS="$TOP"                 # toggle-measurement build: no binds
else
    SNAP="${ip}_sim";  TOPS="$TOP$EXTRA_TOPS"      # normal build: + bind top
fi

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
    local dbg=""
    [ "$wave" = 1 ] && dbg="-debug typical"      # signal visibility for the waveform database
    echo ">> [elab] xelab $UVM_LIB -timescale $TIMESCALE $TOPS -s $SNAP ${covargs:+(+coverage)} $dbg"
    # $TOPS is intentionally unquoted: one or two top-level module names
    xelab $UVM_LIB -timescale "$TIMESCALE" -relax $TOPS -s "$SNAP" $covargs $dbg
}

do_run() {   # $1=test $2=seed
    local test="$1" seed="$2"
    [ -z "$test" ] && { echo "ERROR: run needs a test name" >&2; exit 2; }
    [ -z "$seed" ] && seed=1
    cd "$sv_dir"
    echo ">> [run] $test seed=$seed snapshot=$SNAP ${want_cov:+cov=$want_cov} ${plusargs:+plusargs=$plusargs}"
    local pa=()
    for p in $plusargs; do pa+=(-testplusarg "${p#+}"); done
    local rc
    if [ "$wave" = 1 ]; then
        mkdir -p "$WAVE_ROOT"
        local wdb="$WAVE_ROOT/${test}_seed${seed}.wdb"
        printf 'log_wave -r /%s\nrun all\nquit\n' "$TOP" > "$sv_dir/wave_run.tcl"
        xsim "$SNAP" -testplusarg "UVM_TESTNAME=$test" "${pa[@]}" -sv_seed "$seed" \
             -wdb "$wdb" -tclbatch "$sv_dir/wave_run.tcl"
        rc=$?
        echo ">> [wave] $wdb"
        echo ">>        open with:  xsim --gui $wdb"
    else
        xsim "$SNAP" -R -testplusarg "UVM_TESTNAME=$test" "${pa[@]}" -sv_seed "$seed"
        rc=$?
    fi
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
    wave)
        set -- $POS; [ -z "${1:-}" ] && { echo "usage: xsim_flow.sh wave <ip_dir> <test> [<seed>]" >&2; exit 2; }
        do_compile && do_elab && do_run "$1" "${2:-1}" ;;
    *) echo "unknown subcommand: $cmd" >&2; exit 2 ;;
esac
