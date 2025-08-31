#!/usr/bin/env just --justfile

# Akri Development on macOS using Lima VM
#
# Quick Start:
#   just build              # Build the project
#   just test               # Run tests
#
# The VM starts automatically and stops when done to save resources.

set shell := ["bash", "-euc"]

_vm := "akri-dev"
_config := justfile_directory() / "lima-akri.yaml"

# Build the project
build *ARGS='':
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    # Create VM if it doesn't exist
    if ! limactl list {{_vm}} 2>/dev/null | grep -q {{_vm}}; then
        echo "Creating VM for first time use..."
        limactl create --name={{_vm}} {{_config}}
    fi
    
    # Start VM if not running
    limactl start {{_vm}} 2>/dev/null || true
    
    # Build
    limactl shell {{_vm}} -- bash -c "cd /workspace/akri && source ~/.cargo/env && cargo build {{ARGS}}"

# Run tests
test *ARGS='':
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    # Create VM if it doesn't exist
    if ! limactl list {{_vm}} 2>/dev/null | grep -q {{_vm}}; then
        echo "Creating VM for first time use..."
        limactl create --name={{_vm}} {{_config}}
    fi
    
    # Start VM if not running
    limactl start {{_vm}} 2>/dev/null || true
    
    # Test
    limactl shell {{_vm}} -- bash -c "cd /workspace/akri && source ~/.cargo/env && cargo test {{ARGS}}"