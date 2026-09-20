# vip/pwm — passive PWM / timer-output UVC

Registry key: `interfaces.pwm` in [`flow/config/vip_registry.yaml`](../../flow/config/vip_registry.yaml)
(`path: vip/pwm`, `tracks: [sv-uvm]`, `status: ready`).

Observation-only UVC for an IP that drives one or more PWM-style output pins. It exists so that a
PWM waveform can be checked and covered **from outside the DUT** — every white-box assertion bound
inside a channel is blind to the thing software actually cares about, which is the pin.

## Contents

| File | What it is |
|---|---|
| `sv/pwm_if.sv` | `pwm_if #(NUM_PINS)` — `clk`, `rst_n` and `pwm[NUM_PINS-1:0]` as interface **input ports**, so the UVC is passive by construction and physically cannot drive the DUT. |
| `sv/pwm_item.sv` | `pwm_item` — one transaction per observed event: `PWM_RISE` / `PWM_FALL` (with `hold_cycles`), `PWM_WINDOW` (periodic activity sample: `edges_in_window`, `level`), `PWM_RESET`. |
| `sv/pwm_agent_cfg.sv` | `pwm_agent_cfg #(NUM_PINS)` — `vif`, `num_pins`, `activity_window`, `en_edge_items`. |
| `sv/pwm_monitor.sv` | `pwm_monitor #(NUM_PINS)` — samples every clock, publishes on `ap`. Observes only; never checks. |
| `sv/pwm_agent.sv` | `pwm_agent #(NUM_PINS)` — passive container (no driver/sequencer; there is nothing to drive). |
| `sv/pwm_pkg.sv`, `sv/pwm.f` | package + filelist (compile `pwm_if.sv` first — interfaces cannot live in a package). |

Coverage and checking are deliberately **not** here: bin names and reference models are IP-specific
and belong in the consuming environment's `dv/sv/env/`.

## Wiring it up

```systemverilog
// tb_top
pwm_if #(.NUM_PINS(4)) pwm_ivf (.clk(pclk), .rst_n(presetn), .pwm(pwm_out));
uvm_config_db#(virtual pwm_if#(4))::set(null, "*", "pwm_vif", pwm_ivf);
```

```systemverilog
// env — one typedef per specialization keeps the config_db key types identical
typedef virtual pwm_if#(4) my_pwm_vif_t;
typedef pwm_agent_cfg#(4)  my_pwm_cfg_t;
typedef pwm_agent#(4)      my_pwm_agent_t;
...
pwm_agt.mon.ap.connect(my_pwm_coverage.analysis_export);   // and/or a reference-model checker
```

`activity_window` (default 64 clocks) controls how often a `PWM_WINDOW` item is emitted per pin.
That item is what lets a subscriber distinguish *toggling* from *held low* / *held high* without
re-deriving it from the edge stream; set it to `0` to get edge items only.
