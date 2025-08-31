#!/usr/bin/env just --justfile

# Akri Development on macOS using Lima VM
#
# Quick Start:
#   just build              # Build the project
#   just test               # Run unit tests
#   just test-e2e           # Run end-to-end tests (requires k3s in VM)
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

# Run unit tests
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

# Setup k3s cluster in VM for integration testing
k3s-setup:
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    # Ensure VM exists and is running
    if ! limactl list {{_vm}} 2>/dev/null | grep -q {{_vm}}; then
        echo "Creating VM for first time use..."
        limactl create --name={{_vm}} {{_config}}
    fi
    limactl start {{_vm}} 2>/dev/null || true
    
    # Install k3s
    limactl shell {{_vm}} -- bash -c "
        if ! command -v k3s &> /dev/null; then
            echo 'Installing k3s...'
            curl -sfL https://get.k3s.io | sh -
            sudo mkdir -p ~/.kube
            sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
            sudo chown \$(id -u):\$(id -g) ~/.kube/config
        else
            echo 'k3s already installed'
        fi
    "

# Setup Python test environment
test-setup: k3s-setup
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    limactl start {{_vm}} 2>/dev/null || true
    
    # Install Python dependencies for e2e tests
    limactl shell {{_vm}} -- bash -c "
        cd /workspace/akri
        if ! command -v poetry &> /dev/null; then
            echo 'Installing Poetry...'
            curl -sSL https://install.python-poetry.org | python3 -
            echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc
        fi
        
        # Install Helm
        if ! command -v helm &> /dev/null; then
            echo 'Installing Helm...'
            curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        fi
        
        cd test/e2e
        ~/.local/bin/poetry install
    "

# Run end-to-end tests  
test-e2e SUITE='': test-setup build
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    limactl start {{_vm}} 2>/dev/null || true
    
    # Run e2e tests
    limactl shell {{_vm}} -- bash -c "
        cd /workspace/akri/test/e2e
        source ~/.bashrc
        export KUBECONFIG=~/.kube/config
        poetry run pytest -v --distribution k3s {{SUITE}}
    "

# Run debug echo discovery handler test
test-debug-echo: k3s-setup build
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    limactl start {{_vm}} 2>/dev/null || true
    
    # Install Akri with debug echo
    limactl shell {{_vm}} -- bash -c "
        export KUBECONFIG=~/.kube/config
        
        # Add Akri helm repo
        helm repo add akri-helm-charts https://project-akri.github.io/akri/ || true
        helm repo update
        
        # Install Akri with debug echo discovery handler
        helm install akri akri-helm-charts/akri \
            --set agent.allowDebugEcho=true \
            --set debugEcho.discovery.enabled=true \
            --set debugEcho.configuration.enabled=true \
            --set debugEcho.configuration.brokerPod.image.repository=nginx \
            --set debugEcho.configuration.brokerPod.image.tag=stable-alpine \
            --set debugEcho.configuration.shared=false
        
        # Wait for pods to be ready
        kubectl wait --for=condition=ready pod -l name=akri-agent --timeout=300s
        kubectl wait --for=condition=ready pod -l name=akri-controller --timeout=300s
        
        # Show status
        kubectl get pods,akric,akrii,services -o wide
    "

# Clean up test environment
test-clean: 
    #!/bin/bash
    set -euo pipefail
    
    if limactl list {{_vm}} 2>/dev/null | grep -q {{_vm}}; then
        limactl start {{_vm}} 2>/dev/null || true
        
        # Uninstall Akri if installed
        limactl shell {{_vm}} -- bash -c "
            export KUBECONFIG=~/.kube/config
            helm uninstall akri 2>/dev/null || true
        " || true
        
        limactl stop {{_vm}} 2>/dev/null || true
    fi

# Run specific component build
build-component COMPONENT:
    @just build -p {{COMPONENT}}

# Run specific component test  
test-component COMPONENT:
    @just test -p {{COMPONENT}}

# Build with all features (agent-full)
build-full:
    @just build --features "agent-full udev-feat opcua-feat onvif-feat"

# Clean build artifacts
clean:
    #!/bin/bash
    set -euo pipefail
    trap 'limactl stop {{_vm}} 2>/dev/null || true' EXIT
    
    if ! limactl list {{_vm}} 2>/dev/null | grep -q {{_vm}}; then
        echo "VM doesn't exist"
        exit 0
    fi
    
    limactl start {{_vm}} 2>/dev/null || true
    limactl shell {{_vm}} -- bash -c "cd /workspace/akri && source ~/.cargo/env && cargo clean"