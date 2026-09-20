# Static/generation toolchain container for the VLSI front-end flow.
#   docker build -t vlsi-frontend:latest -f env/Dockerfile .
#   docker run --rm -it -v "$PWD":/work -w /work vlsi-frontend:latest bash
#
# NOTE: this image provides the free helper toolchain only — Verible (lint), Yosys
# + sv2v (synthesizability), Verilator/Icarus (optional lint/elab), and PeakRDL
# (register/RAL/doc generation). It deliberately does NOT contain the UVM
# simulator: UVM sign-off runs on AMD Vivado xsim, which is a manual, licensed
# install (free ML Standard) — see env/README.md. Run xsim in a WSL2/host env.
FROM ubuntu:24.04

ARG VERIBLE_TAG=v0.0-3946-g851d3ff4
ARG SV2V_TAG=v0.0.13
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      git make g++ python3 python3-pip python3-venv \
      iverilog yosys verilator wget curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Verible + sv2v release binaries
RUN wget -q "https://github.com/chipsalliance/verible/releases/download/${VERIBLE_TAG}/verible-${VERIBLE_TAG}-linux-static-x86_64.tar.gz" -O /tmp/verible.tgz \
    && tar -xzf /tmp/verible.tgz -C /tmp && cp /tmp/verible-*/bin/* /usr/local/bin/ && rm -rf /tmp/verible* \
    && wget -q "https://github.com/zachjs/sv2v/releases/download/${SV2V_TAG}/sv2v-Linux.zip" -O /tmp/sv2v.zip \
    && unzip -q /tmp/sv2v.zip -d /tmp && cp /tmp/sv2v-*/sv2v /usr/local/bin/ && rm -rf /tmp/sv2v*

# Register-generation + flow scripting (NO cocotb/pyuvm)
RUN pip3 install --no-cache-dir --break-system-packages \
      "peakrdl>=1.1" "peakrdl-regblock>=1.1" "peakrdl-uvm>=2.2" \
      "peakrdl-html>=2.10" "peakrdl-cheader>=1.0" "systemrdl-compiler>=1.27" \
      "jinja2>=3.1" "pyyaml>=6.0" "jsonschema>=4.0"

CMD ["bash"]
