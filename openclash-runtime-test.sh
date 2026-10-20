set -eu
testdir=/tmp/ps5-mihomo-validation
mkdir -p "$testdir"
cat >"$testdir/config.yaml" <<'EOF'
mixed-port: 47893
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: warning
ipv6: false
external-controller: 127.0.0.1:47990
secret: ps5-vm-validation-only
dns:
  enable: false
rules:
  - MATCH,DIRECT
EOF
core=/etc/openclash/core/clash_meta
"$core" -v
"$core" -t -d "$testdir" -f "$testdir/config.yaml"
"$core" -d "$testdir" -f "$testdir/config.yaml" >"$testdir/runtime.log" 2>&1 &
core_pid=$!
trap 'kill "$core_pid" 2>/dev/null || true; wait "$core_pid" 2>/dev/null || true' EXIT
attempt=0
while ! curl --noproxy '*' -fsS -H 'Authorization: Bearer ps5-vm-validation-only' http://127.0.0.1:47990/version >"$testdir/version.json"; do
    attempt=$((attempt+1))
    test "$attempt" -lt 20 || { cat "$testdir/runtime.log"; exit 1; }
    sleep 1
done
cat "$testdir/version.json"
curl --noproxy '' -fsS --max-time 15 --proxy http://127.0.0.1:47893 http://10.0.2.2:18888/probe.txt >"$testdir/proxy-response.txt"
cat "$testdir/proxy-response.txt"
grep -q PS5_OPENWRT_FORWARDING_OK "$testdir/proxy-response.txt"
echo 'MIHOMO_HTTP_PROXY_AND_API_OK'
