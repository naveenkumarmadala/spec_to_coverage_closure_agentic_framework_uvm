# Getting Started — zero to a running UVM simulation

This guide assumes you know **nothing** about this project yet — not WSL2, not Claude Code, not
Vivado xsim. If you're a fresher, a grad student, or just new to this repo, start here. Everyone else
can skip to [`README.md`](README.md) or [`commands.md`](commands.md).

By the end you will have: the free helper toolchain, **Vivado xsim** (the UVM simulator), a basic
understanding of how this framework talks to you, and the reference IP (`pmtpc4`, a 4-channel
timer/PWM controller) whose SystemVerilog UVM environment you can compile, elaborate, and run yourself.

**Time**: ~1–2 hours, most of it the Vivado download/install running unattended.
**You need**: Windows 10 (2004+) or Windows 11, admin rights, and **~60 GB free disk** (Vivado is large).

---

## Step 0 — Three things you're about to use, in one paragraph each

**WSL2** (Windows Subsystem for Linux) is a real Linux system that runs alongside Windows. The
toolchain (Vivado, PeakRDL, Verible) runs on Linux; WSL2 is how you run it without a
separate machine.

**Vivado xsim** is AMD's SystemVerilog simulator. It is the one tool here that isn't open-source, but
its **free "ML Standard" edition** needs no license file and runs complete UVM — native constrained
randomization, functional + code coverage, and assertions. It's the reason this framework can run a
full UVM testbench on a zero-cost setup.

**Claude Code** is the AI coding assistant this framework is built for. This repo isn't a program you
run directly — it's a set of instructions (`.claude/agents,skills,commands/`) that Claude Code reads
and follows. The `/vlsi-ingest`, `/vlsi-close-coverage`, etc. commands only mean something *inside a
Claude Code chat* — typing them into a plain terminal does nothing.

---

## Step 1 — Install WSL2 + Ubuntu

Open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu-24.04
```

- If this is the first time WSL has been enabled, Windows will ask you to **restart**. Do that.
- An Ubuntu window then finishes installing and asks you to **create a Linux username and password**
  (separate from your Windows login). **Remember this password** — every `sudo` later needs it.
- **Put the WSL distro on a drive with real free space.** Vivado needs ~50 GB inside WSL; if your
  C: drive is tight, move the distro to another drive (`wsl --export` / `--unregister` / `--import`).

Once you see a prompt like `yourname@YOURPC:~$`, WSL2 + Ubuntu is ready.

---

## Step 2 — Install Claude Code

Follow **claude.com/claude-code** for your platform. The common path (with Node.js installed):

```bash
npm install -g @anthropic-ai/claude-code
```

The VS Code / JetBrains extensions and the desktop app work with this repo the same way.

---

## Step 3 — Install the free helper toolchain **yourself**

> **Do this by hand, in a real terminal — not by asking Claude Code.** The script installs packages
> with `sudo`, which waits for your password in the terminal; Claude Code can't answer that prompt.

Open your Ubuntu/WSL terminal, `cd` to wherever this repo lives (`/mnt/d/...` or a Linux-home clone
for faster I/O), then run:

```bash
bash env/bootstrap-wsl2.sh
```

This installs (all free): **Verible** (lint) and a Python venv with **PeakRDL** (SystemRDL→RTL/RAL)
and the flow's scripting deps. Everything else — the static gate's elaboration and synthesis,
simulation, coverage — runs on Vivado, installed in the next step. **No cocotb/pyuvm** — verification is
pure SystemVerilog UVM on xsim.

It prints a version table at the end; if anything says `MISSING`, re-run it (safe to repeat).

---

## Step 4 — Install Vivado xsim (the UVM simulator)

This is the one manual, larger install. Full detail is in [`env/README.md`](env/README.md); the short
version, **inside WSL**:

```bash
sudo apt install -y libtinfo5 libncurses5 libx11-6 libxrender1 libxtst6 libxi6 default-jre
```

1. Sign in to an AMD account, download the **"AMD Unified Installer for FPGAs & Adaptive SoCs — Linux
   Self Extracting Web Installer"** (2024.1 or newer), copy it into WSL.
2. Run it, choose edition **"Vivado ML Standard"** (free, no license), install to `/tools/Xilinx`.
3. Put it on PATH and verify:
   ```bash
   source /tools/Xilinx/2025.1/Vivado/settings64.sh   # add this line to ~/.bashrc
   xvlog --version && xsim --version
   ```

xsim ships a precompiled UVM 1.2 (used via `-L uvm`), so nothing else is needed to start.

---

## Step 5 — Open the repo in Claude Code

- **VS Code / JetBrains**: open this repo's folder from *within* WSL (`code .` in the repo dir).
- **CLI**: `cd` into the repo in your WSL terminal and run `claude`.

From here, **every `/vlsi-...` command is typed into the Claude Code chat — not the plain terminal.**

---

## Step 6 — Run the reference IP: `pmtpc4`

`pmtpc4` (a 4-channel timer/PWM controller) is the reference IP: its complete SystemVerilog UVM
environment compiles, elaborates, and runs on xsim. Prove your setup works by running it **yourself**
in the WSL terminal (quick, deterministic — no Claude Code needed):

```bash
source /tools/Xilinx/2025.1/Vivado/settings64.sh          # if not already on PATH
bash flow/scripts/xsim_flow.sh smoke ips/pmtpc4 pmtpc4_sanity_test
```

You should see the UVM report summary with `UVM_ERROR : 0` / `UVM_FATAL : 0` and the scoreboard
reporting `checks=… errors=0`. That single command just compiled real SystemVerilog RTL + a full UVM
testbench, elaborated it, and ran a real simulation with assertions and a reference-model scoreboard —
on your machine, on the free toolchain.

Run the full seeded regression (every test × N seeds, with coverage):

```bash
python3 flow/scripts/run_regression.py ips/pmtpc4
```

In the Claude Code chat, `/vlsi-status pmtpc4` reports which stages/artifacts exist and what to run
next. See [`commands.md`](commands.md) for the full command sequence.

---

## Step 7 — Bring your own IP

Start your own IP the way `pmtpc4` started: with a requirement document. In the Claude Code chat:

```
/vlsi-ingest path/to/your_requirement_spec.md my_ip_name
```

`spec-ingestor` reads your document, drafts a config + first-cut requirements, then **stops and asks
you to review it** — nothing downstream runs on an unconfirmed guess. Correct anything wrong, approve,
and the pipeline runs from there. [`README.md`](README.md) has every stage; [`commands.md`](commands.md)
has the exact sequence.

---

## Troubleshooting — real problems

| Symptom | What's going on | Fix |
|---|---|---|
| `wsl --install` does nothing / unknown command | Windows too old, or WSL never enabled | Update Windows, or follow Microsoft's manual WSL2 steps |
| Claude Code says it's stuck at a `sudo` prompt | That's Step 3's password prompt — the agent can't answer it | Run `bash env/bootstrap-wsl2.sh` yourself in a real WSL terminal |
| `xvlog: command not found` | `settings64.sh` isn't sourced in this shell | `source /tools/Xilinx/2025.1/Vivado/settings64.sh` (add it to `~/.bashrc`); the flow scripts also source `$VIVADO_SETTINGS` |
| Vivado binaries abort with `locale::facet::_S_create_c_locale` | `en_US.UTF-8` locale not generated | `sudo locale-gen en_US.UTF-8 && sudo update-locale`, and export `LANG`/`LC_ALL` before the Vivado source line |
| Vivado installer can't find `libtinfo5`/`libncurses5` | Newer Ubuntu dropped these from its repos | Install the compatible `.deb`s from the Jammy/22.04 universe pool (old-releases.ubuntu.com) |
| Vivado install fills the disk / WSL runs out of space | Vivado needs ~50 GB inside WSL | Put the WSL distro on a drive with space; install to `/tools/Xilinx` on that drive |
| A long background install silently dies | WSL2's VM auto-shuts down when idle | Set `vmIdleTimeout=-1` in `C:\Users\<you>\.wslconfig` |
| xsim I/O feels slow | Running from `/mnt/*` (a Windows drive) | Works fine; for speed, clone the repo into the Linux home filesystem |

---

## Where to go next

- [`README.md`](README.md) — the full architecture: every agent, skill, and command, with diagrams.
- [`commands.md`](commands.md) — the exact command sequence from setup through coverage closure.
- [`env/README.md`](env/README.md) — toolchain + Vivado install reference.
- [`docs/architecture.md`](docs/architecture.md) — deeper design rationale and phased roadmap.
