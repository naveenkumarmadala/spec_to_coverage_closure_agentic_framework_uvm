#!/usr/bin/env python3
"""Validate an ip_config.yaml against flow/config/ip_config.schema.json.

Usage:
    python flow/scripts/validate_config.py ips/<ip>/ip_config.yaml

Exits 0 if valid, 1 otherwise. Also applies a few cross-field sanity checks
that JSON Schema alone cannot express (e.g. bus.clock must name a real clock).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import yaml
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit("Missing deps. Activate the venv: source env/.venv/bin/activate")

REPO = Path(__file__).resolve().parents[2]
SCHEMA = REPO / "flow" / "config" / "ip_config.schema.json"
VIP_REGISTRY = REPO / "flow" / "config" / "vip_registry.yaml"


def load_registry() -> dict:
    """Load the pluggable VIP registry (buses + interfaces). Missing file is tolerated."""
    if not VIP_REGISTRY.exists():
        return {}
    return yaml.safe_load(VIP_REGISTRY.read_text()) or {}


def cross_checks(cfg: dict) -> tuple[list[str], list[str]]:
    """Return (hard_errors, warnings). Warnings don't fail validation."""
    errs: list[str] = []
    warns: list[str] = []
    clocks = {c["name"] for c in cfg.get("clocks", [])}
    resets = {r["name"] for r in cfg.get("resets", [])}
    bus = cfg.get("bus", {})
    if bus.get("clock") and bus["clock"] not in clocks:
        errs.append(f"bus.clock '{bus['clock']}' is not a declared clock {sorted(clocks)}")
    if bus.get("reset") and bus["reset"] not in resets:
        errs.append(f"bus.reset '{bus['reset']}' is not a declared reset {sorted(resets)}")
    for r in cfg.get("resets", []):
        if r.get("clock") and r["clock"] not in clocks:
            errs.append(f"reset '{r['name']}' references unknown clock '{r['clock']}'")

    # Protocol-agnostic check: bus.protocol and interfaces[].kind must resolve in the
    # VIP registry (not a fixed enum). Unknown -> actionable "register a VIP" message.
    reg = load_registry()
    reg_buses = set((reg.get("buses") or {}).keys())
    reg_ifaces = set((reg.get("interfaces") or {}).keys())
    proto = bus.get("protocol")
    if proto and reg_buses and proto not in reg_buses and not bus.get("vip"):
        errs.append(
            f"bus.protocol '{proto}' is not in vip_registry.yaml (buses: {sorted(reg_buses)}). "
            f"Add an entry there + a VIP under vip/, or set bus.vip to a custom VIP path."
        )
    for i in cfg.get("interfaces", []):
        k = i.get("kind")
        if k and reg_ifaces and k not in reg_ifaces and not i.get("vip"):
            errs.append(
                f"interface '{i.get('name')}' kind '{k}' is not in vip_registry.yaml "
                f"(interfaces: {sorted(reg_ifaces)}). Register it, or set its 'vip' override."
            )
    # A registry entry that isn't 'ready' yet is fine — just note it.
    if proto in reg_buses and (reg["buses"][proto].get("status") != "ready"):
        warns.append(f"bus VIP for '{proto}' is '{reg['buses'][proto].get('status')}' (not yet implemented)")

    # Subsystem interconnect protocol (if present) also resolves against the registry.
    sub = cfg.get("subsystem")
    if sub:
        ic = (sub.get("interconnect") or {}).get("protocol")
        if ic and reg_buses and ic not in reg_buses:
            errs.append(f"subsystem.interconnect.protocol '{ic}' is not in vip_registry.yaml (buses: {sorted(reg_buses)}).")

    # The SystemRDL source is a later-phase (P2) artifact, so a missing file is a
    # warning, not a hard failure — the config itself is still valid.
    src = cfg.get("registers", {}).get("source")
    if src and not (Path(sys.argv[1]).parent / src).exists():
        warns.append(f"registers.source '{src}' not found yet (expected before P2/registers stage)")
    return errs, warns


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    cfg_path = Path(sys.argv[1])
    cfg = yaml.safe_load(cfg_path.read_text())
    schema = json.loads(SCHEMA.read_text())

    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(cfg), key=lambda e: e.path)
    cross_errs, warns = cross_checks(cfg)
    problems = [f"  [schema] {'/'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in errors]
    problems += [f"  [cross ] {m}" for m in cross_errs]

    for w in warns:
        print(f"  [warn  ] {w}")
    if problems:
        print(f"INVALID: {cfg_path}")
        print("\n".join(problems))
        return 1
    print(f"OK: {cfg_path} ({cfg['ip']['name']} v{cfg['ip']['version']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
