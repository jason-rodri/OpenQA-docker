#!/bin/bash
# Start OpenVSwitch daemons and create the bridge required by os-autoinst-openvswitch.
set -euo pipefail

LOG=/var/log/openqa/ovs-setup.log
mkdir -p /run/openvswitch /var/log/openvswitch

echo "[ovs-setup] initializing OVS database..." | tee -a "$LOG"
[ -f /etc/openvswitch/conf.db ] || \
    ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema

echo "[ovs-setup] starting ovsdb-server..." | tee -a "$LOG"
ovsdb-server /etc/openvswitch/conf.db \
    --remote=punix:/run/openvswitch/db.sock \
    --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
    --pidfile=/run/openvswitch/ovsdb-server.pid \
    --detach --log-file=/var/log/openvswitch/ovsdb-server.log

until ovs-vsctl --no-wait show > /dev/null 2>&1; do sleep 0.5; done
ovs-vsctl --no-wait init

echo "[ovs-setup] starting ovs-vswitchd..." | tee -a "$LOG"
ovs-vswitchd unix:/run/openvswitch/db.sock \
    --pidfile=/run/openvswitch/ovs-vswitchd.pid \
    --detach --log-file=/var/log/openvswitch/ovs-vswitchd.log

until ovs-vsctl show > /dev/null 2>&1; do sleep 0.5; done

echo "[ovs-setup] creating OVS bridge br-openqa..." | tee -a "$LOG"
ovs-vsctl --may-exist add-br br-openqa
ip addr add 10.0.2.2/15 dev br-openqa 2>/dev/null || true
ip link set br-openqa up

echo "[ovs-setup] bridge br-openqa ready at 10.0.2.2/15" | tee -a "$LOG"

# Monitor OVS daemons; exit if either dies so supervisord can restart us
while true; do
    if ! kill -0 "$(cat /run/openvswitch/ovsdb-server.pid 2>/dev/null)" 2>/dev/null || \
       ! kill -0 "$(cat /run/openvswitch/ovs-vswitchd.pid 2>/dev/null)" 2>/dev/null; then
        echo "[ovs-setup] OVS daemon exited — triggering restart" | tee -a "$LOG"
        exit 1
    fi
    sleep 5
done
