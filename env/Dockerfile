# Static/generation toolchain container for the VLSI front-end flow.
#   docker build -t vlsi-frontend:latest -f env/Dockerfile .
#   docker run --rm -it -v "$PWD":/work -w /work vlsi-frontend:latest bash
#
# NOTE: this image provides only Verible (lint) and PeakRDL (register/RAL/doc
# generation) plus the flow scripts' Python. It deliberately does NOT contain
# Vivado, which runs the rest of the flow (static-gate elaboration + synthesis,
# UVM simulation, coverage): a manual install (free ML Standard) — see
# env/README.md. Run Vivado in a WSL2/host env.
FROM ubuntu:24.04

ARG VERIBLE_TAG=v0.0-3946-g851d3ff4
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      git make g++ python3 python3-pip python3-venv \
      wget curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Verible release binary
RUN wget -q "https://github.com/chipsalliance/verible/releases/download/${VERIBLE_TAG}/verible-${VERIBLE_TAG}-linux-static-x86_64.tar.gz" -O /tmp/verible.tgz \
    && tar -xzf /tmp/verible.tgz -C /tmp && cp /tmp/verible-*/bin/* /usr/local/bin/ && rm -rf /tmp/verible*

# Register-generation + flow scripting (NO cocotb/pyuvm)
RUN pip3 install --no-cache-dir --break-system-packages \
      "peakrdl>=1.1" "peakrdl-regblock>=1.1" "peakrdl-uvm>=2.2" \
      "peakrdl-html>=2.10" "peakrdl-cheader>=1.0" "systemrdl-compiler>=1.27" \
      "jinja2>=3.1" "pyyaml>=6.0" "jsonschema>=4.0" "openpyxl>=3.1"

CMD ["bash"]
