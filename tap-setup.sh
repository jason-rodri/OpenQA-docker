#!/bin/bash
#
# TAP Networking Setup Script for OpenQA Container
#
# This script configures TAP networking inside the openQA container
# to enable multi-machine tests.
#
# Author: Jason Rodriguez
# Date: 2026-04-03

set -e

echo "=== OpenQA TAP Networking Setup ==="
echo "Started: $(date)"

# Check if running as root or with NET_ADMIN
if ! ip link show > /dev/null 2>&1; then
    echo "ERROR: Cannot manage network devices. Need NET_ADMIN capability."
    exit 1
fi

# Check if TUN/TAP device is available
if [ ! -c /dev/net/tun ]; then
    echo "ERROR: /dev/net/tun device not available"
    echo "Make sure the container has access to /dev/net/tun"
    exit 1
fi

echo "✓ TUN/TAP device available: /dev/net/tun"

# Install required packages if not present
if ! command -v brctl &> /dev/null; then
    echo "Installing bridge-utils..."
    dnf install -y bridge-utils iproute iptables
fi

# Create bridge for TAP devices (if not exists)
BRIDGE_NAME="br-tap"

if ! ip link show "$BRIDGE_NAME" &> /dev/null; then
    echo "Creating bridge: $BRIDGE_NAME"
    ip link add name "$BRIDGE_NAME" type bridge
    ip link set "$BRIDGE_NAME" up

    # Assign IP to bridge (172.16.2.1)
    ip addr add 172.16.2.1/24 dev "$BRIDGE_NAME" || {
        echo "Note: Bridge IP already assigned or conflict"
    }
else
    echo "✓ Bridge already exists: $BRIDGE_NAME"
    ip link set "$BRIDGE_NAME" up
fi

# Display bridge information
echo ""
echo "Bridge configuration:"
ip addr show "$BRIDGE_NAME"
echo ""

# Enable IP forwarding (set by docker-compose sysctl; best-effort write here)
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true

# Setup NAT for TAP bridge (allows VMs to reach external network)
echo "Configuring NAT..."

# Get the default route interface
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -n "$DEFAULT_IFACE" ]; then
    echo "Default interface: $DEFAULT_IFACE"

    # Add NAT rule (if not already present)
    if ! iptables -t nat -C POSTROUTING -s 172.16.2.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s 172.16.2.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE
        echo "✓ NAT rule added"
    else
        echo "✓ NAT rule already exists"
    fi
else
    echo "WARNING: Could not determine default interface for NAT"
fi

# Allow forwarding from bridge
iptables -A FORWARD -i "$BRIDGE_NAME" -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -o "$BRIDGE_NAME" -j ACCEPT 2>/dev/null || true

echo ""
echo "=== TAP Networking Setup Complete ==="
echo ""
echo "Bridge: $BRIDGE_NAME (172.16.2.1/24)"
echo "TAP devices will be added to this bridge by openQA worker"
echo ""
echo "Test with:"
echo "  ip link show $BRIDGE_NAME"
echo "  ip tuntap add mode tap tap-test"
echo "  ip link set tap-test master $BRIDGE_NAME"
echo "  ip link set tap-test up"
echo "  ip link delete tap-test"
echo ""
