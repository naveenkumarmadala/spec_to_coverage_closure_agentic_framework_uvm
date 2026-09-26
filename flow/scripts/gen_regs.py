#!/usr/bin/env python3
"""
gen_regs.py — generate an IP's register outputs from its SystemRDL with PeakRDL, using ONLY the
options recorded in ip_config.yaml, so the generated RTL is reproducible from a fresh clone.

Outputs (under <ip>/<dir of registers.source>/generated/, git-ignored):
    rtl/<module>.sv, rtl/<package>.sv, rtl/<module>_hwif.rpt   peakrdl regblock
    <ip>_ral_pkg.sv                                             peakrdl uvm
    html/                                                       peakrdl html
    <ip>.h                                                      peakrdl c-header

ip_config.yaml (all `regblock` keys optional):
    registers:
      source: rdl/<ip>.rdl
      top_component: <addrmap>        # -> --top
      regblock:
        cpuif: apb4-flat              # default: vip_registry buses.<bus.protocol>.cpuif
        module_name: <ip>_regblock    # default shown
        package_name: <ip>_regblock_pkg
        default_reset: arst_n         # default: from the bus reset in `resets:` (sync/async x high/low)

Run with the framework venv (it has PeakRDL):
    env/.venv/bin/python3 flow/scripts/gen_regs.py ips/<ip>
"""
import subprocess, sys
from pathlib import Path
import yaml

FRAMEWORK = Path(__file__).resolve().parents[2]
RESET_STYLE = {("sync", "high"): "rst", ("sync", "low"): "rst_n",
               ("async", "high"): "arst", ("async", "low"): "arst_n"}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen_regs.py ips/<ip>")
    ip_dir = Path(sys.argv[1]).resolve()
    cfg = yaml.safe_load((ip_dir / "ip_config.yaml").read_text())
    ip = cfg["ip"]["name"]
    regs = cfg["registers"]
    rb = regs.get("regblock", {}) or {}

    cpuif = rb.get("cpuif")
    if not cpuif:
        reg = yaml.safe_load((FRAMEWORK / "flow" / "config" / "vip_registry.yaml").read_text())
        cpuif = reg["buses"][cfg["bus"]["protocol"]]["cpuif"]
    default_reset = rb.get("default_reset")
    if not default_reset:
        rst = next(r for r in cfg["resets"] if r["name"] == cfg["bus"]["reset"])
        default_reset = RESET_STYLE[(rst.get("sync", "sync"), rst.get("active_level", "high"))]
    module = rb.get("module_name", f"{ip}_regblock")
    package = rb.get("package_name", f"{ip}_regblock_pkg")

    rdl = ip_dir / regs["source"]
    gen = rdl.parent / "generated"
    (gen / "rtl").mkdir(parents=True, exist_ok=True)   # regblock opens the hwif report before creating dirs
    top = ["--top", regs["top_component"]] if regs.get("top_component") else []
    peakrdl = str(Path(sys.executable).parent / "peakrdl")
    cmds = [
        ["regblock", str(rdl), *top, "-o", str(gen / "rtl"), "--cpuif", cpuif,
         "--module-name", module, "--package-name", package,
         "--default-reset", default_reset, "--hwif-report"],
        ["uvm", str(rdl), *top, "-o", str(gen / f"{ip}_ral_pkg.sv")],
        ["html", str(rdl), *top, "-o", str(gen / "html")],
        ["c-header", str(rdl), *top, "-o", str(gen / f"{ip}.h")],
    ]
    print(f"gen_regs: {ip}: cpuif={cpuif} module={module} package={package} default_reset={default_reset}")
    for c in cmds:
        r = subprocess.run([peakrdl, *c], capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout + r.stderr)
            sys.exit(f"gen_regs: peakrdl {c[0]} failed")
        print(f"   peakrdl {c[0]:9s} ok")


if __name__ == "__main__":
    main()
