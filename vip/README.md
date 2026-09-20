# vip/ — reusable Verification IP

Build-once, use-everywhere agents and utilities. This is what keeps the flow **generic**: an IP's
`dv/` contains only IP-specific glue, while all bus/protocol machinery lives here and is instantiated
from config.

```
vip/<bus>/sv/     SystemVerilog UVM agent (driver, monitor, sequencer, seq_item, coverage) for a bus
vip/common/       shared base classes, reg-adapter helpers, scoreboard base, utilities
```

## Planned VIP

| Kind | Phase |
|---|---|
| `apb` / `apb4` bus agent | P3 |
| `gpio` interface agent | P3 |
| `axi4-lite` bus agent | P6 (genericity proof) |
| `spi` / `i2c` / `uart` | as needed |

## Rules
- A bus/interface agent is written **once** here (SystemVerilog UVM) and selected via `ip_config.yaml`
  (`bus.protocol`, `interfaces[].kind`). Never re-implement a bus driver inside an IP's `dv/`.
- Add a new protocol by adding a directory here + a registry entry — no agent/template changes needed.
