"""Verify the built kernel/rootfs through an SSH tunnel into a disposable VM."""
import datetime
import http.client
import http.cookies
import json
import logging
import os
import re
import shlex
from pathlib import Path
import sys
import tempfile
import time
import warnings
from urllib.parse import urlencode

warnings.filterwarnings("ignore")
sys.path.insert(0,str(Path(tempfile.gettempdir())/"codex-ps5-ssh-deps"))
import paramiko
logging.getLogger('paramiko').setLevel(logging.CRITICAL)

ROOT="/home/ub/ps5-openwrt-13.00"
host=paramiko.SSHClient()
host.load_system_host_keys()
host.connect(os.environ.get("PS5_BUILD_HOST","127.0.0.1"),int(os.environ.get("PS5_BUILD_PORT","22")),username=os.environ.get("PS5_BUILD_USER","ub"),password=os.environ["PS5_BUILD_SSH_PASSWORD"],look_for_keys=False,allow_agent=False,timeout=15)
host.get_transport().set_keepalive(20)
result={"tested_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"environment":"QEMU/TCG snapshot with PS5-only initcalls skipped", "ps5_hardware_tested":False,"test_only_initcall_blacklist":["mp1_init","ps5_fan_init","ps5_led_init","ps5_buzzer_init","spcie_driver_init","tpcie_driver_init"],"checks":[]}
guest=None
try:
    with host.open_sftp() as sftp:
        with sftp.open(ROOT+"/private/root-password.txt") as file:password=file.read().decode().strip()
    deadline=time.monotonic()+180
    print("Waiting for test VM SSH",flush=True)
    last_error=None
    while time.monotonic()<deadline:
        try:
            channel=host.get_transport().open_channel("direct-tcpip",("127.0.0.1",12222),("127.0.0.1",0),timeout=5)
            guest=paramiko.SSHClient()
            guest.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            guest.connect("ps5-openwrt-test-vm",username="root",password=password,sock=channel,look_for_keys=False,allow_agent=False,timeout=8,banner_timeout=8,auth_timeout=8)
            break
        except Exception as error:
            last_error=str(error)
            if guest:guest.close();guest=None
            time.sleep(3)
    if guest is None:raise RuntimeError("VM SSH unavailable: "+str(last_error))
    result["checks"].append({"name":"SSH password login","passed":True})
    def check(name,command,expect=None,timeout=45):
        _,out,err=guest.exec_command(command,timeout=timeout)
        text=out.read().decode(errors="replace")
        errors=err.read().decode(errors="replace")
        status=out.channel.recv_exit_status()
        passed=status==0 and (expect is None or expect in text)
        entry={"name":name,"passed":passed,"exit_status":status,"stdout":text[:14000],"stderr":errors[:3000]}
        result["checks"].append(entry)
        print(name+": "+("PASS" if passed else "FAIL"),flush=True)
        if not passed:raise RuntimeError(name+" failed: "+text+errors)
        return text
    check("PS5 kernel boot","uname -r","7.1.7-ps5-openwrt")
    check("OpenWrt services","ubus call system board","25.12.6")
    check("Hostname and logging service","test \"$(cat /proc/sys/kernel/hostname)\" = PS5-OpenWrt && test \"$(ubus list log)\" = log && echo SYSTEM_CONFIG_OK","SYSTEM_CONFIG_OK")
    check("Chinese interface","uci get luci.main.lang","zh_cn")
    check("Network configuration preserved",'''test "$(uci get network.lan.proto)" = dhcp && test "$(uci get network.rescue.ipaddr)" = 172.31.55.1 && echo NETWORK_PRESERVED''',"NETWORK_PRESERVED")
    check("LAN bridge uses wired MAC and upstream DHCP",'''test "$(uci get network.lan.device)" = br-lan && test "$(uci get network.rescue.device)" = br-lan && test "$(uci get network.ps5_lan_bridge.ports)" = eth0 && test "$(cat /sys/class/net/br-lan/address)" = "$(cat /sys/class/net/eth0/address)" && test -e /sys/class/net/br-lan/brif/eth0 && ubus call network.interface.lan status''','"l3_device": "br-lan"')
    check("Automatic CN channel 36 open AP defaults",'''test "$(uci get wireless.radio0.phy)" = mwiphy0 && test "$(uci get wireless.radio0.disabled)" = 0 && test "$(uci get wireless.radio0.country)" = CN && test "$(uci get wireless.radio0.channel)" = 36 && test "$(uci get wireless.radio0.band)" = 5g && test "$(uci get wireless.default_radio0.mode)" = ap && test "$(uci get wireless.default_radio0.ssid)" = PS5-OpenWrt && test "$(uci get wireless.default_radio0.encryption)" = none && test "$(uci get wireless.default_radio0.disabled)" = 0 && test "$(uci get wireless.default_radio0.network)" = lan && echo AP_DEFAULTS_OK''',"AP_DEFAULTS_OK")
    if password != "password":raise RuntimeError("Requested default root password was not set")
    check("Compiled Argon theme is selected",'''test "$(uci get luci.main.mediaurlbase)" = /luci-static/argon && apk info -e luci-theme-argon && test -s /www/luci-static/argon/css/cascade.css && echo ARGON_SELECTED''',"ARGON_SELECTED")
    check("RTL8156B matching driver and firmware",'''test -d /sys/module/r8152 && test -s /lib/firmware/rtl_nic/rtl8156b-2.fw && test -f /lib/modules/7.1.7-ps5-openwrt/r8152.ko && echo RTL8156B_DRIVER_AND_FIRMWARE_PRESENT''',"RTL8156B_DRIVER_AND_FIRMWARE_PRESENT")
    check("PS5 IW620 modules load against matching kernel",'''modprobe cfg80211 && modprobe mlan && { test -d /sys/module/moal || insmod /lib/modules/7.1.7-ps5-openwrt/moal.ko fw_name=nxp/pcieuartiw620_combo_v1.bin pcie_int_mode=1 drv_mode=1 cfg80211_wext=4 sta_name=mlan ext_scan=1 auto_fw_reload=0 wifi_reset_config=0 sched_scan=0 ps_mode=2 auto_ds=2 amsdu_disable=1; } && test -d /sys/module/moal && test -d /sys/module/mlan && echo IW620_MODULE_ABI_OK''',"IW620_MODULE_ABI_OK")
    check("Wireless tools and boot firmware service",'''apk info -e ps5-iw620 wifi-scripts iw iwinfo wpad-basic-mbedtls wireless-regdb && test -s /lib/firmware/regulatory.db && test -x /etc/init.d/ps5-wifi && test -L /etc/rc.d/S19ps5-wifi && test "$(uci get fstab.ps5_boot.label)" = boot && iw list && echo WIRELESS_USERSPACE_PRESENT''',"WIRELESS_USERSPACE_PRESENT")
    check("Signed regulatory database is integrated",'''test -s /lib/firmware/regulatory.db.p7s && cmp /usr/share/ps5-openwrt/regdb/regulatory.db /lib/firmware/regulatory.db && cmp /usr/share/ps5-openwrt/regdb/regulatory.db.p7s /lib/firmware/regulatory.db.p7s && iw reg reload && ! dmesg | grep -E 'regulatory.db.*(failed|malformed)|signature is missing/invalid' && apk list --installed ps5-iw620''',"7.1.7-r5")
    check("Fan plugin defaults, native control tool and startup",'''apk info -e luci-app-ps5-fan && test -L /etc/rc.d/S17ps5-fan && command -v flock && test "$(uci get ps5_fan.main.target)" = 80 && uci set ps5_fan.main.mode=max && /etc/init.d/ps5-fan start && test "$(uci get ps5_fan.main.mode)" = auto && ! /usr/sbin/ps5_control --fan invalid >/tmp/ps5-control-invalid.log 2>&1 && grep -q 'Invalid fan state' /tmp/ps5-control-invalid.log && echo FAN_BOOT_AUTO_OK''',"FAN_BOOT_AUTO_OK")
    fan=json.loads(check("Fan RPC status without hardware","ubus call ps5.fan status"))
    if not fan.get('ok') or fan.get('hardware_available') or fan.get('target')!=80 or fan.get('percentage_control'):
        raise RuntimeError('Fan RPC hardware absence or default settings incorrect')
    rejected=json.loads(check("Fan RPC rejects invalid control input",'''ubus call ps5.fan apply '{"mode":"auto","target":0}' '''))
    if rejected.get('ok') is not False:raise RuntimeError('Invalid fan target accepted')
    previous=os.environ.get('PS5_COREMARK_VALIDATION_REVISION')
    if previous:
        if previous!='pre-lan-ap-20261020':raise RuntimeError('Unexpected validation revision')
        base=ROOT+'/work/revisions/'+previous
        with host.open_sftp() as sftp:
            with sftp.open(base+'/output/validation-vm.json') as file:prior=json.loads(file.read())
        mark=next(item for item in prior['checks'] if 'CoreMark' in item['name'])
        assert prior['passed'] and mark['passed'] and re.search(r'Parallel\s+PThreads\s*:\s*16\b',mark['stdout'])
        _,out,err=host.exec_command('sha256sum '+shlex.quote(base+'/rootfs/bin/coremark'))
        expected=out.read().decode().split()[0]
        assert out.channel.recv_exit_status()==0
        check('CoreMark binary matches previously validated 16-thread build','sha256sum /bin/coremark',expected)
        result['checks'][-1]['previous_runtime_validation']=base+'/output/validation-vm.json'
        result['checks'][-1]['previous_default_threads']=16
    else:
        coremark=check("Compiled CoreMark benchmark with 16 default threads",'''apk list --installed coremark && cd /tmp && /bin/coremark''',"Correct operation validated.",timeout=180)
        if not re.search(r'Parallel\s+PThreads\s*:\s*16\b',coremark):
            result['checks'][-1]['passed']=False
            raise RuntimeError('CoreMark did not run with the requested 16 default threads: '+coremark)
    check("DHCP servers disabled","test \"$(uci get dhcp.lan.ignore)\" = 1 && test \"$(uci get dhcp.rescue.ignore)\" = 1 && ! netstat -uln | grep -Eq ':[6]7[[:space:]]' && echo DHCP_SERVER_DISABLED","DHCP_SERVER_DISABLED")
    check('LAN bridge forwards client DHCP to upstream router',Path(__file__).with_name('lan-bridge-dhcp-test.sh').read_text(encoding='utf-8'),'LAN_BRIDGE_UPSTREAM_DHCP_AND_CLIENT_TRAFFIC_OK',timeout=60)
    check("Firewall syntax and required kernel features","fw4 check && nft list ruleset | grep masquerade","masquerade")
    check("Signed PS5 kernel package","apk info -e kernel && apk list --installed kernel","7.1.7-r1003")
    check('Hardware-validated MTS bridge repair preserved', '''test "$(sha256sum /lib/modules/7.1.7-ps5-openwrt/mts.ko | cut -d' ' -f1)" = 6311f35a077bc5993bb4faef608ed7371006ef369ea1903b5653a474aa315f7a && test -s /usr/share/ps5-openwrt/ps5-bridge-hardware-validation.json && echo MTS_REPAIR_PRESERVED''', 'MTS_REPAIR_PRESERVED')
    check('OpenClash and Mihomo installed with disabled unconfigured service', '''apk info -e luci-app-openclash mihomo ps5-openclash-support luci-compat && test "$(uci get openclash.config.enable)" = 0 && test "$(uci get openclash.config.core_type)" = Meta && test -x /etc/openclash/core/clash_meta && test -s /usr/lib/lua/luci/controller/openclash.lua && ! pidof clash_meta && echo OPENCLASH_PREINSTALLED''', 'OPENCLASH_PREINSTALLED')
    check('OpenClash Ruby YAML and full DNS dependencies', '''apk info -e dnsmasq-full bash curl ruby ruby-yaml unzip && dnsmasq --version | grep -w nftset && bash -c 'test 3 -eq $((1+2))' && ruby -ryaml -e 'abort unless YAML.safe_load("core: Mihomo")["core"] == "Mihomo"; puts "YAML_OK"' ''', 'YAML_OK')
    check('OpenClash TUN TPROXY and connection diagnostic kernel features', '''set -e
modprobe inet_diag
modprobe tcp_diag
modprobe udp_diag
ip tuntap add dev ps5-clash-tun mode tun
ip link del ps5-clash-tun
cat >/tmp/ps5-clash-tproxy.nft <<'EOF'
table inet ps5_clash_probe {
 chain prerouting {
  type filter hook prerouting priority mangle; policy accept;
  meta l4proto { tcp, udp } tproxy to :7895 meta mark set 1 accept
 }
}
EOF
nft --check -f /tmp/ps5-clash-tproxy.nft
echo CLASH_KERNEL_FEATURES_OK''', 'CLASH_KERNEL_FEATURES_OK')
    check('Mihomo actual HTTP proxy and authenticated API', Path(__file__).with_name('openclash-runtime-test.sh').read_text(encoding='utf-8'), 'MIHOMO_HTTP_PROXY_AND_API_OK', timeout=60)
    check("WireGuard kernel and userspace","ip link add wg-probe type wireguard && wg show wg-probe && ip link del wg-probe")
    def http_request(method,path,body=None,headers=None):
        connection=http.client.HTTPConnection("127.0.0.1",18080,timeout=20)
        connection.sock=host.get_transport().open_channel("direct-tcpip",("127.0.0.1",18080),("127.0.0.1",0),timeout=10)
        connection.request(method,path,body=body,headers=headers or {})
        response=connection.getresponse();data=response.read()
        status=response.status;response_headers=dict(response.getheaders())
        connection.close()
        return status,response_headers,data
    status,headers,body=http_request("GET","/cgi-bin/luci/")
    # LuCI uses HTTP 403 for its normal unauthenticated login form.
    ok=status in (200,403) and b'luci_password' in body and b'lang="zh-cn"' in body and b'/luci-static/argon/' in body
    result["checks"].append({"name":"Chinese LuCI login page","passed":ok,"http_status":status,"html_bytes":len(body)})
    print("LuCI login page: "+("PASS" if ok else "FAIL"),flush=True)
    if not ok:raise RuntimeError("LuCI HTTP test failed")
    status,headers,body=http_request("GET","/luci-static/argon/css/cascade.css")
    ok=status==200 and len(body)>1000
    result["checks"].append({"name":"Argon stylesheet HTTP delivery","passed":ok,"http_status":status,"bytes":len(body)})
    if not ok:raise RuntimeError("Argon stylesheet HTTP delivery failed")
    request={"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":password,"timeout":60}]}
    status,headers,body=http_request("POST","/ubus/",json.dumps(request),{"Content-Type":"application/json"})
    reply=json.loads(body)
    ok=status==200 and reply.get('result',[1])[0]==0 and bool(reply['result'][1].get('ubus_rpc_session'))
    result['checks'].append({'name':'LuCI RPC password authentication','passed':ok,'http_status':status})
    print('LuCI RPC password authentication: '+('PASS' if ok else 'FAIL'),flush=True)
    if not ok:raise RuntimeError('LuCI RPC authentication failed')
    session=reply['result'][1]['ubus_rpc_session']
    status,headers,body=http_request('POST','/cgi-bin/luci/',urlencode({'luci_username':'root','luci_password':password}),{'Content-Type':'application/x-www-form-urlencoded'})
    cookie=http.cookies.SimpleCookie()
    cookie.load(headers.get('Set-Cookie',headers.get('set-cookie','')))
    ok=status in (302,303) and 'sysauth_http' in cookie
    result['checks'].append({'name':'LuCI browser form authentication','passed':ok,'http_status':status})
    if not ok:raise RuntimeError('LuCI browser form authentication failed')
    auth_cookie='; '.join(k+'='+v.value for k,v in cookie.items())
    status,headers,body=http_request('GET','/cgi-bin/luci/admin/services/openclash',headers={'Cookie':auth_cookie})
    ok=status==200 and b'OpenClash' in body and b'luci_password' not in body
    result['checks'].append({'name':'Authenticated OpenClash LuCI page','passed':ok,'http_status':status,'bytes':len(body)})
    if not ok:raise RuntimeError('OpenClash LuCI page unavailable: HTTP '+str(status)+' '+body[:500].decode(errors='replace'))
    request={'jsonrpc':'2.0','id':2,'method':'call','params':[session,'ps5.fan','status',{}]}
    status,headers,body=http_request('POST','/ubus/',json.dumps(request),{'Content-Type':'application/json'})
    fan_reply=json.loads(body)
    ok=status==200 and fan_reply.get('result',[1])[0]==0 and fan_reply['result'][1].get('ok') is True
    result['checks'].append({'name':'Authenticated LuCI fan RPC','passed':ok})
    if not ok:raise RuntimeError('Authenticated fan RPC unavailable')
    request={'jsonrpc':'2.0','id':3,'method':'call','params':['00000000000000000000000000000000','ps5.fan','apply',{'mode':'max','target':80}]}
    status,headers,body=http_request('POST','/ubus/',json.dumps(request),{'Content-Type':'application/json'})
    denied=json.loads(body)
    ok=denied.get('error',{}).get('code')==-32002 or denied.get('result',[0])[0]==6
    result['checks'].append({'name':'Unauthenticated fan changes denied','passed':ok,'reply':denied})
    if not ok:raise RuntimeError('Unauthenticated fan control was accepted')
    status,headers,body=http_request('GET','/luci-static/resources/view/system/ps5-fan.js')
    ok=status==200 and '手动全速'.encode() in body and b'ps5.fan' in body
    result['checks'].append({'name':'LuCI fan page JavaScript delivered','passed':ok,'http_status':status,'bytes':len(body)})
    if not ok:raise RuntimeError('Fan view asset unavailable')
    command=r'''set -e
ip netns add ps5-probe
trap 'ip netns del ps5-probe 2>/dev/null || true; ip link del ps5-probe-r 2>/dev/null || true' EXIT
ip link add ps5-probe-r type veth peer name ps5-probe-c
ip link set ps5-probe-c netns ps5-probe
ip addr add 172.20.55.1/24 dev ps5-probe-r
ip link set ps5-probe-r up
ip netns exec ps5-probe ip link set lo up
ip netns exec ps5-probe ip addr add 172.20.55.2/24 dev ps5-probe-c
ip netns exec ps5-probe ip link set ps5-probe-c up
ip netns exec ps5-probe ip route add default via 172.20.55.1
uci add_list firewall.@zone[0].device=ps5-probe-r
fw4 reload
ip netns exec ps5-probe wget -q -T 15 -O - http://10.0.2.2:18888/probe.txt
echo
grep 'src=172.20.55.2 dst=10.0.2.2' /proc/net/nf_conntrack | grep 'dst=10.0.2.15'
uci set dhcp.@dnsmasq[0].noresolv=1
uci add_list dhcp.@dnsmasq[0].server='10.0.2.2#1053'
/etc/init.d/dnsmasq restart
sleep 3
ip netns exec ps5-probe nslookup -type=A ps5-openwrt-probe.example.com 172.20.55.1
'''
    network=check("Forwarding, source NAT and DNS proxy",command,"93.184.216.34")
    if "PS5_OPENWRT_FORWARDING_OK" not in network:raise RuntimeError("Forwarding marker missing")
    check("Generic image upgrade blocked","! ( . /lib/upgrade/platform.sh; platform_check_image /tmp/nonexistent ) && echo GENERIC_UPGRADE_BLOCKED","GENERIC_UPGRADE_BLOCKED")
    result["passed"]=True
except Exception as error:
    result["passed"]=False
    result["error"]=str(error)
    print("VALIDATION FAILED:",error,flush=True)
finally:
    output=Path(__file__).parent/os.environ.get("PS5_VALIDATION_LOCAL_DIR","output")
    output.mkdir(exist_ok=True)
    data=json.dumps(result,indent=2,ensure_ascii=False)+"\n"
    (output/"validation-vm.json").write_text(data,encoding="utf-8")
    with host.open_sftp() as sftp:
        with sftp.open(ROOT+"/output/validation-vm.json","w") as file:file.write(data)
    if guest:guest.close()
    host.close()
sys.exit(0 if result.get("passed") else 1)
