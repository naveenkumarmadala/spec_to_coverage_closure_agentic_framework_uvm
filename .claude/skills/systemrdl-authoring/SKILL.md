---
name: systemrdl-authoring
description: How to author SystemRDL 2.0 register descriptions and drive PeakRDL to generate register-block RTL, the UVM RAL model, C headers, and HTML docs. Use whenever creating or modifying an IP's register map (the ip_config registers.source file).
---

# Authoring SystemRDL + driving PeakRDL

SystemRDL is the **single source of truth** for registers. One `.rdl` file → RTL, UVM RAL, C
headers, and docs, so those views can never drift apart.

## File skeleton

```systemrdl
addrmap apb_gpio {
    name = "APB GPIO + Timer";
    desc = "Implements REQ-010..REQ-030"; // trace to requirements in desc text
    default regwidth = 32;
    default accesswidth = 32;

    reg {
        name = "Direction";
        desc = "1=output, 0=input per pin. Implements REQ-011.";
        field { sw=rw; hw=r; reset=0; } DIR[31:0];
    } DIR @ 0x00;

    reg {
        name = "Output data";
        field { sw=rw; hw=r; reset=0; } DOUT[31:0];
    } DOUT @ 0x04;

    reg {
        name = "Input data";
        field { sw=r; hw=w; } DIN[31:0];   // hw writes sampled pins
    } DIN @ 0x08;

    reg {
        name = "Interrupt status";
        desc = "Interrupt-on-change, write-1-to-clear. Implements REQ-020.";
        field { sw=rw; hw=w; woclr; reset=0; } ISR[31:0];
    } ISR @ 0x0C;
};
```

## Field property cheat-sheet (the ones you actually need)

| Property | Meaning |
|---|---|
| `sw = rw \| r \| w` | software access |
| `hw = rw \| r \| w \| na` | hardware access (does RTL read or write the field?) |
| `reset = <val>` | reset value (checked by the RAL reset sequence) |
| `woclr` / `woset` | write-one-to-clear / -set (status/interrupt regs) |
| `rclr` / `rset` | clear/set on read |
| `we` / `wel` | hardware write-enable / -enable-low |
| `counter` | field increments in hardware (timers) |
| `intr` + `enable`/`mask` | interrupt field semantics (RAL + RTL model these) |
| `singlepulse` | asserts one cycle then self-clears |

## Generate (WSL2, venv active)

```bash
# regblock RTL + UVM RAL + HTML + C header; options from ip_config.yaml registers.regblock
# (cpuif defaults to the bus's registry cpuif, reset style to the bus reset) -- never hand-typed
env/.venv/bin/python3 flow/scripts/gen_regs.py ips/<ip>
# register-bit toggle config for the reusable reg_bit_toggle_cov (the RDL's singlepulse fields)
env/.venv/bin/python3 flow/scripts/gen_reg_toggle_cfg.py ips/<ip>   # -> dv/sv/env/<ip>_reg_toggle_cfg.svh
```

- Pick `--cpuif` to match `bus.protocol` in `ip_config.yaml`.
- The regblock exposes a `hwif_in`/`hwif_out` struct — the RTL connects hardware logic to these.
- **Re-run `gen_reg_toggle_cfg.py` after every RDL change** (`run_regression.py` also does it
  automatically when the `.svh` is missing or older than the RDL). Mark self-clearing command bits
  `singlepulse` in the RDL rather than hand-coding them anywhere: that property is what tells the
  register-bit toggle coverage that a bus read can never show them as 1.
- The generated regblock's **code toggle is not measurable on xsim** (its field flops are nested
  structs; its `automatic` next-value temporaries are listed but never updated). `gen_exclusions.py`
  scopes everything under `generated/rtl/` out of the toggle report automatically; the register
  storage is measured by `reg_bit_toggle_cov` instead.

## Rules & gotchas

- Match `regwidth`/`accesswidth` to `bus.data_width`. Address offsets must fit `bus.addr_width`. Once
  set, **don't narrow it later to shrink a coverage tool's dead-bit residual** — `regwidth`/
  `accesswidth` is coupled to register address stride/alignment in PeakRDL's generated address map,
  not just data-path width, so narrowing it ripples into the register spec, RAL, C headers, and every
  hardcoded address literal already written against the wider map. A register whose fields are all
  narrower than the bus (e.g. every field ≤16 bits on a 32-bit bus) is normal, unremarkable design —
  the resulting dead upper bits are a `coverage-triage` waiver/residual item, not a register-map defect
  to redesign around. **The correct, safe fix for the READBACK side's coverage consequence is a
  top-level RTL split of the regblock's `cpuif_rd_data` port** (`rtl-designer`'s job, informed by the
  widest field's top bit you report after generating) — never the address map. That technique touches
  zero address offsets or register semantics; narrowing `regwidth` touches both. The WRITE side
  (`cpuif_wr_data`) is not the same case and doesn't get this split — see `rtl-designer`/
  `coverage-triage` for why (the unused bits there are a stimulus gap, not a structural one).
- Every field's `reset`, `sw`, `hw` must match the design spec — the RAL will assert on mismatches.
- Keep a REQ/SPEC ID in each `desc` so register coverage rolls up to requirements.
- Never hand-edit files under `generated/`; change the RDL and regenerate.
- Compile-check first: PeakRDL errors are precise — read the file:line and fix the RDL.
