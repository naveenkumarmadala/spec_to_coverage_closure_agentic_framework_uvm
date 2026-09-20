# Pilot IP — `apb_gpio` (APB4 GPIO + Timer)

The reference IP used to prove the flow end-to-end before generalizing. Register-heavy by design so
it exercises the full SystemRDL → PeakRDL → RAL → register-coverage path.

## What it is
A 32-bit **APB4 subordinate** peripheral: 32 bidirectional GPIO with per-pin direction, output data,
input sampling, interrupt-on-change, plus a free-running 32-bit timer with a programmable compare
interrupt. Single clock (`pclk`), async-assert/sync-deassert reset (`presetn`).

Config: [`ip_config.yaml`](ip_config.yaml) (validate with
`python ../../flow/scripts/validate_config.py ip_config.yaml`).

## Directory
```
spec/     requirements.md, design_spec.md            (P1)
rdl/      apb_gpio.rdl + generated/ (PeakRDL output)  (P2)
rtl/      apb_gpio.sv + sub-blocks                    (P2)
vplan/    vplan.yaml                                   (P4)
dv/sv/    SystemVerilog UVM environment (runs on xsim) (P3+)
reports/  coverage + regression output                (P5)
```

## Drive it
```
/vlsi-spec apb_gpio
/vlsi-registers apb_gpio
/vlsi-rtl apb_gpio
/vlsi-build-env apb_gpio
/vlsi-verify apb_gpio
/vlsi-close-coverage apb_gpio
```
or the whole thing: `/vlsi-flow apb_gpio`. Status any time: `/vlsi-status apb_gpio`.

> Contents beyond `ip_config.yaml` are produced by the flow in phases P1–P5.
