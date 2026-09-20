// PMTPC-4 static-gate DUT RTL file list (Verilator lint-only / Yosys
// elaboration -- see dv/README.md "Static gate"). Order matters: the
// regblock package must be listed before the files that `import` it.
//
// Paths are relative to the repo root, matching the working directory the
// static-gate commands in dv/README.md are run from.
//
// This mirrors the DUT RTL section of dv/sv/filelist.f (paths there are
// relative to dv/sv/, for simulation) -- keep the two lists in sync if the
// RTL file set changes; true single-sourcing needs a build-system include
// mechanism, which is a later-phase (P2+ flow/tools) concern.
ips/pmtpc4/rdl/generated/rtl/pmtpc4_regblock_pkg.sv
ips/pmtpc4/rdl/generated/rtl/pmtpc4_regblock.sv
ips/pmtpc4/rtl/pmtpc4_prescaler.sv
ips/pmtpc4/rtl/pmtpc4_channel.sv
ips/pmtpc4/rtl/pmtpc4_apb_slave.sv
ips/pmtpc4/rtl/pmtpc4.sv
