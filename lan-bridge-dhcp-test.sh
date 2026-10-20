set -eu
ip netns add ps5-ap-client
trap 'ip netns del ps5-ap-client 2>/dev/null || true; ip link del ap-bridge-probe 2>/dev/null || true; rm -f /tmp/ps5-ap-dhcp-hook /tmp/ps5-ap-dhcp.lease' EXIT
ip link add ap-bridge-probe type veth peer name ap-client0
ip link set ap-client0 netns ps5-ap-client
ip link set ap-bridge-probe master br-lan
ip link set ap-bridge-probe up
ip netns exec ps5-ap-client ip link set lo up
ip netns exec ps5-ap-client ip link set ap-client0 address 02:55:01:00:00:02
ip netns exec ps5-ap-client ip link set ap-client0 up
cat >/tmp/ps5-ap-dhcp-hook <<'EOF'
#!/bin/sh
set -e
case "$1" in
    bound|renew)
        test "$subnet" = 255.255.255.0
        ip addr flush dev "$interface"
        ip addr add "$ip/24" dev "$interface"
        ip route replace default via "${router%% *}" dev "$interface"
        printf 'ip=%s\nserver=%s\nrouter=%s\n' "$ip" "$serverid" "$router" >/tmp/ps5-ap-dhcp.lease
        ;;
esac
EOF
chmod 755 /tmp/ps5-ap-dhcp-hook
ip netns exec ps5-ap-client udhcpc -f -n -q -i ap-client0 -t 6 -T 3 -s /tmp/ps5-ap-dhcp-hook
cat /tmp/ps5-ap-dhcp.lease
grep -Fx 'server=10.0.2.2' /tmp/ps5-ap-dhcp.lease
grep -Fx 'router=10.0.2.2' /tmp/ps5-ap-dhcp.lease
ip netns exec ps5-ap-client ip -4 addr show dev ap-client0
ip netns exec ps5-ap-client wget -q -T 15 -O - http://10.0.2.2:18888/probe.txt
echo 'LAN_BRIDGE_UPSTREAM_DHCP_AND_CLIENT_TRAFFIC_OK'
