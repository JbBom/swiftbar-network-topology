#!/bin/zsh

# SwiftBar plugin: read-only network topology monitor.
# Filename interval ".10s" makes SwiftBar refresh every 10 seconds.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PROXY_PORT="${PROXY_PORT:-10808}"
EXTERNAL_LATENCY_WARN_MS="${EXTERNAL_LATENCY_WARN_MS:-3000}"
GATEWAY_LATENCY_WARN_MS="${GATEWAY_LATENCY_WARN_MS:-80}"

safe_run() {
  "$@" 2>/dev/null
}

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

country_flag() {
  local code="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  case "$code" in
    US) echo "🇺🇸" ;;
    CN) echo "🇨🇳" ;;
    HK) echo "🇭🇰" ;;
    TW) echo "🇹🇼" ;;
    JP) echo "🇯🇵" ;;
    SG) echo "🇸🇬" ;;
    KR) echo "🇰🇷" ;;
    GB|UK) echo "🇬🇧" ;;
    DE) echo "🇩🇪" ;;
    FR) echo "🇫🇷" ;;
    CA) echo "🇨🇦" ;;
    AU) echo "🇦🇺" ;;
    NL) echo "🇳🇱" ;;
    *) echo "🏳️" ;;
  esac
}

country_cn() {
  local code="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  case "$code" in
    US) echo "美国" ;;
    CN) echo "中国" ;;
    HK) echo "中国香港" ;;
    TW) echo "中国台湾" ;;
    JP) echo "日本" ;;
    SG) echo "新加坡" ;;
    KR) echo "韩国" ;;
    GB|UK) echo "英国" ;;
    DE) echo "德国" ;;
    FR) echo "法国" ;;
    CA) echo "加拿大" ;;
    AU) echo "澳大利亚" ;;
    NL) echo "荷兰" ;;
    *) echo "未知国家" ;;
  esac
}

iface_bytes() {
  local ifc="$1"
  netstat -ibn 2>/dev/null | awk -v ifc="$ifc" '$1 == ifc && $3 ~ /^<Link/ {print $(NF-4), $(NF-1); exit}'
}

process_bytes() {
  local proc="$1"
  local out
  if [ -z "$proc" ] || [ "$proc" = "-" ]; then
    echo "- -"
    return
  fi
  out="$(nettop -P -J bytes_in,bytes_out -x -l 1 2>/dev/null | awk -v proc="$proc" '{for (i = 1; i <= NF; i++) if ($i ~ ("^" proc "\\.")) {print $(NF-1), $NF; exit}}')"
  if [ -n "$out" ]; then
    echo "$out"
  else
    echo "- -"
  fi
}

format_activity_rate() {
  local rate="$1"
  case "$rate" in
    ""|"-") echo "$rate" ;;
    "calibrating") echo "校准中" ;;
    "0 B/s") echo "空闲" ;;
    *) echo "$rate" ;;
  esac
}

infer_vpn_name() {
  if pgrep -x "aTrustXtunnel" >/dev/null 2>&1 || pgrep -x "aTrustAgent" >/dev/null 2>&1 || pgrep -x "aTrust" >/dev/null 2>&1; then
    echo "aTrust"
  elif pgrep -x "CloudflareWARP" >/dev/null 2>&1 || pgrep -x "Cloudflare WARP" >/dev/null 2>&1; then
    echo "Cloudflare WARP"
  elif pgrep -ix "Surge" >/dev/null 2>&1; then
    echo "Surge"
  elif pgrep -ix "Clash" >/dev/null 2>&1 || pgrep -ix "Clash Verge" >/dev/null 2>&1 || pgrep -ix "mihomo" >/dev/null 2>&1; then
    echo "Clash / Mihomo"
  elif pgrep -ix "sing-box" >/dev/null 2>&1; then
    echo "sing-box"
  elif pgrep -ix "WireGuard" >/dev/null 2>&1; then
    echo "WireGuard"
  elif pgrep -ix "OpenVPN" >/dev/null 2>&1; then
    echo "OpenVPN"
  else
    echo "未知 VPN"
  fi
}

app_name_from_path() {
  local file_path="$1"
  local app
  app="$(echo "$file_path" | sed -n 's#.*\/\([^/]*\.app\)\/.*#\1#p' | sed 's/\.app$//' | head -n 1)"
  if [ -n "$app" ]; then
    echo "$app"
  else
    basename "$file_path"
  fi
}

infer_proxy_app() {
  local pid="$1"
  local current="$pid"
  local comm app depth
  depth=0
  while [ -n "$current" ] && [ "$current" != "1" ] && [ "$depth" -lt 8 ]; do
    comm="$(ps -p "$current" -o comm= 2>/dev/null | trim)"
    app="$(app_name_from_path "$comm")"
    case "$app" in
      v2rayN|Clash*|Surge|Stash|Loon|Quantumult*|sing-box|mihomo|Shadowrocket|Outline|WireGuard|OpenVPN)
        echo "$app"
        return
        ;;
    esac
    current="$(ps -p "$current" -o ppid= 2>/dev/null | tr -d ' ')"
    depth=$((depth + 1))
  done
  if pgrep -x "v2rayN" >/dev/null 2>&1; then
    echo "v2rayN"
  elif pgrep -ix "Clash" >/dev/null 2>&1 || pgrep -ix "Clash Verge" >/dev/null 2>&1 || pgrep -ix "mihomo" >/dev/null 2>&1; then
    echo "Clash / Mihomo"
  elif pgrep -ix "Surge" >/dev/null 2>&1; then
    echo "Surge"
  elif pgrep -ix "sing-box" >/dev/null 2>&1; then
    echo "sing-box"
  else
    echo "未知代理软件"
  fi
}

format_rate() {
  local bytes_per_sec="$1"
  if [ -z "$bytes_per_sec" ] || [ "$bytes_per_sec" = "-" ]; then
    echo "-"
  elif [ "$bytes_per_sec" -lt 1024 ]; then
    echo "${bytes_per_sec} B/s"
  elif [ "$bytes_per_sec" -lt 1048576 ]; then
    awk -v v="$bytes_per_sec" 'BEGIN {printf "%.1f KB/s", v/1024}'
  else
    awk -v v="$bytes_per_sec" 'BEGIN {printf "%.2f MB/s", v/1048576}'
  fi
}

is_number() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

latency_number() {
  echo "$1" | awk '{gsub(/[^0-9]/, "", $1); print $1}'
}

ping_latency() {
  local host="$1"
  if [ -z "$host" ] || [ "$host" = "-" ]; then
    echo "-"
    return
  fi
  ping -q -c 1 -W 1000 "$host" 2>/dev/null | awk -F'=' '/round-trip|rtt/ {split($2, a, "/"); gsub(/[[:space:]]/, "", a[2]); if (a[2] != "") printf "%.0f ms", a[2]}'
}

web_latency() {
  local proxy="$1"
  local proxy_url
  local timing
  if [ -n "$proxy" ] && [ "$proxy" != "-" ]; then
    if echo "$proxy" | grep -q "://"; then
      proxy_url="$proxy"
    else
      proxy_url="http://$proxy"
    fi
    timing="$(curl --proxy "$proxy_url" -L -m 2 -o /dev/null -s -w "%{time_total}" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  else
    timing="$(curl -L -m 2 -o /dev/null -s -w "%{time_total}" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  fi
  if [ -n "$timing" ]; then
    awk -v v="$timing" 'BEGIN {if (v > 0) printf "%.0f ms", v * 1000}'
  else
    echo "-"
  fi
}

status_line="NET"
health="OK"
problems=()

warp_status="$(safe_run warp-cli status)"
warp_settings="$(safe_run warp-cli settings)"
dns_state="$(safe_run scutil --dns)"
proxy_state="$(safe_run scutil --proxy)"
route_state="$(safe_run route -n get default)"
services_state="$(safe_run networksetup -listallnetworkservices)"

warp_connected="no"
if echo "$warp_status" | grep -Eqi "^Status update:[[:space:]]+Connected$"; then
  warp_connected="yes"
fi

warp_network="$(echo "$warp_status" | awk -F': ' '/Network:/ {print $2; exit}' | trim)"
if [ -z "$warp_network" ]; then
  warp_network="-"
fi

allow_mode_switch="$(echo "$warp_settings" | awk -F': ' '/Allow Mode Switch:/ {print $2; exit}' | trim)"
if [ -z "$allow_mode_switch" ]; then
  allow_mode_switch="-"
elif [ "$allow_mode_switch" != "true" ]; then
  health="WARN"
  problems+=("WARP mode switch is not allowed")
fi

connectivity_disabled="$(echo "$warp_settings" | awk -F': ' '/Connectivity Checks Disabled:/ {print $2; exit}' | trim)"
if [ -z "$connectivity_disabled" ]; then
  connectivity_disabled="false"
fi

warp_mode="$(echo "$warp_settings" | awk -F': ' '/Mode:/ {print $2; exit}' | trim)"
warp_protocol="$(echo "$warp_settings" | awk -F': ' '/WARP tunnel protocol:/ {print $2; exit}' | trim)"
warp_org="$(echo "$warp_settings" | awk -F': ' '/Organization:/ {print $2; exit}' | trim)"

dns_servers="$(echo "$dns_state" | awk '/nameserver\[[0-9]+\] :/ {print $3}' | awk '!seen[$0]++' | paste -sd ', ' -)"
if [ -z "$dns_servers" ]; then
  dns_servers="-"
  health="WARN"
  problems+=("No DNS server detected")
fi

system_proxy="none"
if ! echo "$proxy_state" | grep -q "<dictionary> {"; then
  system_proxy="unknown"
elif echo "$proxy_state" | grep -q "HTTPEnable : 1\\|HTTPSEnable : 1\\|SOCKSEnable : 1"; then
  http_proxy="$(echo "$proxy_state" | awk '/HTTPProxy :/ {host=$3} /HTTPPort :/ {port=$3} END {if (host != "" && port != "") print host ":" port}')"
  https_proxy="$(echo "$proxy_state" | awk '/HTTPSProxy :/ {host=$3} /HTTPSPort :/ {port=$3} END {if (host != "" && port != "") print host ":" port}')"
  socks_proxy="$(echo "$proxy_state" | awk '/SOCKSProxy :/ {host=$3} /SOCKSPort :/ {port=$3} END {if (host != "" && port != "") print host ":" port}')"
  system_proxy="enabled"
fi

env_proxy="${ALL_PROXY:-${HTTPS_PROXY:-${HTTP_PROXY:-none}}}"

gateway="$(echo "$route_state" | awk '/gateway:/ {print $2; exit}' | trim)"
iface="$(echo "$route_state" | awk '/interface:/ {print $2; exit}' | trim)"
if [ -z "$gateway" ]; then
  gateway="-"
fi
if [ -z "$iface" ]; then
  iface="-"
fi

warp_iface="-"
warp_ip="-"
for dev in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep '^utun'); do
  info="$(safe_run ifconfig "$dev")"
  if echo "$info" | grep -q "100\.96\.\|2606:4700:cf1"; then
    warp_iface="$dev"
    warp_ip="$(echo "$info" | awk '/inet / {print $2; exit}' | trim)"
    break
  fi
done

tunnel_names=()
tunnel_ifaces=()
tunnel_ips=()
generic_vpn_name="$(infer_vpn_name)"
for dev in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^(utun|tun|tap|ppp)'); do
  info="$(safe_run ifconfig "$dev")"
  tunnel_ip="$(echo "$info" | awk '/inet / && $2 !~ /^127\\./ && $2 !~ /^169\\.254\\./ {print $2; exit}' | trim)"
  if [ -z "$tunnel_ip" ]; then
    tunnel_ip="$(echo "$info" | awk '/inet6 / && $2 !~ /^fe80:/ {print $2; exit}' | sed 's/%.*//' | trim)"
  fi
  if [ -n "$tunnel_ip" ]; then
    tunnel_name="$generic_vpn_name"
    if [ "$warp_connected" = "yes" ] && [ "$dev" = "$warp_iface" ]; then
      tunnel_name="Cloudflare WARP"
    fi
    tunnel_names+=("$tunnel_name")
    tunnel_ifaces+=("$dev")
    tunnel_ips+=("$tunnel_ip")
  fi
done

system_vpn_active="no"
active_tunnel_iface="-"
active_tunnel_ip="-"
active_tunnel_route_count=0
active_tunnel_route_mode="-"
if [ ${#tunnel_ifaces[@]} -gt 0 ]; then
  system_vpn_active="yes"
  active_tunnel_iface="${tunnel_ifaces[1]}"
  active_tunnel_ip="${tunnel_ips[1]}"
  active_tunnel_route_count="$(netstat -rn -f inet 2>/dev/null | awk -v ifc="$active_tunnel_iface" '$NF == ifc {count++} END {print count + 0}')"
  if [ "$active_tunnel_iface" = "$iface" ]; then
    active_tunnel_route_mode="全局默认路由"
  elif [ "$active_tunnel_route_count" -gt 0 ] 2>/dev/null; then
    active_tunnel_route_mode="分流隧道"
  else
    active_tunnel_route_mode="仅接口在线"
  fi
fi

now_ts="$(date +%s)"
rate_state="/tmp/network-topology-rate.${USER}.state"
en0_bytes="$(iface_bytes en0)"
warp_bytes="- -"
if [ "$active_tunnel_iface" != "-" ]; then
  warp_bytes="$(iface_bytes "$active_tunnel_iface")"
fi
proxy_port="$PROXY_PORT"
proxy_pid="$(safe_run lsof -nP -iTCP:${proxy_port} -sTCP:LISTEN | awk 'NR == 2 {print $2; exit}' | trim)"
proxy_process="$(safe_run lsof -nP -iTCP:${proxy_port} -sTCP:LISTEN | awk 'NR == 2 {print $1; exit}' | trim)"
if [ -z "$proxy_process" ]; then
  proxy_process="-"
fi
if [ -z "$proxy_pid" ]; then
  proxy_pid="-"
fi
proxy_app="-"
if [ "$proxy_pid" != "-" ]; then
  proxy_app="$(infer_proxy_app "$proxy_pid")"
fi
proxy_bytes="$(process_bytes "$proxy_process")"
en0_in="$(echo "$en0_bytes" | awk '{print $1}')"
en0_out="$(echo "$en0_bytes" | awk '{print $2}')"
warp_in="$(echo "$warp_bytes" | awk '{print $1}')"
warp_out="$(echo "$warp_bytes" | awk '{print $2}')"
proxy_in="$(echo "$proxy_bytes" | awk '{print $1}')"
proxy_out="$(echo "$proxy_bytes" | awk '{print $2}')"

en0_rate_down="calibrating"
en0_rate_up="calibrating"
warp_rate_down="calibrating"
warp_rate_up="calibrating"
proxy_rate_down="calibrating"
proxy_rate_up="calibrating"

if [ -f "$rate_state" ]; then
  read -r prev_ts prev_en0_in prev_en0_out prev_warp_iface prev_warp_in prev_warp_out prev_proxy_process prev_proxy_in prev_proxy_out < "$rate_state"
  elapsed=$(( now_ts - prev_ts ))
  if [ "$elapsed" -gt 0 ] 2>/dev/null; then
    if is_number "$en0_in" && is_number "$en0_out" && is_number "$prev_en0_in" && is_number "$prev_en0_out" && [ "$en0_in" -ge "$prev_en0_in" ] 2>/dev/null; then
      en0_rate_down="$(format_rate $(( (en0_in - prev_en0_in) / elapsed )))"
      en0_rate_up="$(format_rate $(( (en0_out - prev_en0_out) / elapsed )))"
    fi
    if [ "$active_tunnel_iface" = "$prev_warp_iface" ] && is_number "$warp_in" && is_number "$warp_out" && is_number "$prev_warp_in" && is_number "$prev_warp_out" && [ "$warp_in" -ge "$prev_warp_in" ] 2>/dev/null; then
      warp_rate_down="$(format_rate $(( (warp_in - prev_warp_in) / elapsed )))"
      warp_rate_up="$(format_rate $(( (warp_out - prev_warp_out) / elapsed )))"
    fi
    if [ "$proxy_process" = "$prev_proxy_process" ] && is_number "$proxy_in" && is_number "$proxy_out" && is_number "$prev_proxy_in" && is_number "$prev_proxy_out" && [ "$proxy_in" -ge "$prev_proxy_in" ] 2>/dev/null; then
      proxy_rate_down="$(format_rate $(( (proxy_in - prev_proxy_in) / elapsed )))"
      proxy_rate_up="$(format_rate $(( (proxy_out - prev_proxy_out) / elapsed )))"
    fi
  fi
fi
echo "$now_ts ${en0_in:-0} ${en0_out:-0} ${active_tunnel_iface:-"-"} ${warp_in:-0} ${warp_out:-0} ${proxy_process:-"-"} ${proxy_in:-0} ${proxy_out:-0}" > "$rate_state"

tailscale_service="unknown"
if echo "$services_state" | grep -q "^\\*Tailscale$"; then
  tailscale_service="disabled"
elif echo "$services_state" | grep -q "^Tailscale$"; then
  tailscale_service="enabled"
  health="WARN"
  problems+=("Tailscale service is enabled")
else
  tailscale_service="not found"
fi

tailscale_binary="not found"
if command -v tailscale >/dev/null 2>&1; then
  if safe_run tailscale status >/dev/null; then
    tailscale_binary="ok"
  else
    tailscale_binary="broken"
  fi
fi

public_ip="-"
public_city="-"
public_country="-"
public_country_code="-"
public_flag="🏳️"
public_org="-"
if command -v ipinfo >/dev/null 2>&1; then
  ipinfo_out="$(safe_run ipinfo myip)"
  public_ip="$(echo "$ipinfo_out" | sed -n 's/^- IP[[:space:]]*//p' | head -n 1 | trim)"
  public_city="$(echo "$ipinfo_out" | sed -n 's/^- City[[:space:]]*//p' | head -n 1 | trim)"
  public_country="$(echo "$ipinfo_out" | sed -n 's/^- Country[[:space:]]*//p' | head -n 1 | trim)"
  public_country_code="$(echo "$public_country" | sed -n 's/.*(\([A-Za-z][A-Za-z]\)).*/\1/p' | head -n 1 | trim)"
  public_org="$(echo "$ipinfo_out" | sed -n 's/^- Organization[[:space:]]*//p' | head -n 1 | trim)"
fi
if [ -z "$public_ip" ] || [ "$public_ip" = "-" ]; then
  public_lookup_proxy=""
  if [ -n "$http_proxy" ]; then
    if echo "$http_proxy" | grep -q "://"; then
      public_lookup_proxy="$http_proxy"
    else
      public_lookup_proxy="http://$http_proxy"
    fi
  elif [ -n "$socks_proxy" ]; then
    if echo "$socks_proxy" | grep -q "://"; then
      public_lookup_proxy="$socks_proxy"
    else
      public_lookup_proxy="socks5h://$socks_proxy"
    fi
  fi
  if [ -n "$public_lookup_proxy" ]; then
    ipinfo_json="$(curl --proxy "$public_lookup_proxy" -L -m 3 -s https://ipinfo.io/json 2>/dev/null)"
  else
    ipinfo_json="$(curl -L -m 3 -s https://ipinfo.io/json 2>/dev/null)"
  fi
  public_ip="$(echo "$ipinfo_json" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  public_city="$(echo "$ipinfo_json" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  public_country_code="$(echo "$ipinfo_json" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  public_org="$(echo "$ipinfo_json" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
fi
if [ -z "$public_ip" ] || [ "$public_ip" = "-" ]; then
  if [ -n "$public_lookup_proxy" ]; then
    cf_trace="$(curl --proxy "$public_lookup_proxy" -L -m 3 -s https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  else
    cf_trace="$(curl -L -m 3 -s https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  fi
  public_ip="$(echo "$cf_trace" | awk -F= '$1 == "ip" {print $2; exit}' | trim)"
  public_country_code="$(echo "$cf_trace" | awk -F= '$1 == "loc" {print $2; exit}' | trim)"
  public_city="$(echo "$cf_trace" | awk -F= '$1 == "colo" {print $2; exit}' | trim)"
  if [ -n "$public_ip" ]; then
    public_org="Cloudflare trace"
  fi
fi
if [ -z "$public_ip" ]; then
  public_ip="-"
fi
if [ -z "$public_city" ]; then
  public_city="-"
fi
if [ -z "$public_country_code" ]; then
  public_country_code="-"
else
  public_flag="$(country_flag "$public_country_code")"
fi
public_country_name="$(country_cn "$public_country_code")"
if [ "$public_country_code" != "-" ]; then
  public_country_label="$public_country_name $public_country_code"
else
  public_country_label="$public_country_name"
fi
if [ -z "$public_org" ]; then
  public_org="-"
fi

proxy_label="none"
if [ "$system_proxy" = "enabled" ]; then
  proxy_label="${http_proxy:-${socks_proxy:-enabled}}"
elif [ "$env_proxy" != "none" ]; then
  proxy_label="$env_proxy"
fi

gateway_latency="$(ping_latency "$gateway")"
if [ -z "$gateway_latency" ]; then
  gateway_latency="-"
fi

latency_proxy=""
if [ -n "$http_proxy" ]; then
  latency_proxy="$http_proxy"
elif [ -n "$socks_proxy" ]; then
  latency_proxy="socks5h://$socks_proxy"
fi
exit_latency="$(web_latency "$latency_proxy")"
if [ -z "$exit_latency" ]; then
  exit_latency="-"
fi

gateway_latency_ms="$(latency_number "$gateway_latency")"
exit_latency_ms="$(latency_number "$exit_latency")"
external_slow="no"
lan_slow="no"
if is_number "$exit_latency_ms" && [ "$exit_latency_ms" -ge "$EXTERNAL_LATENCY_WARN_MS" ]; then
  external_slow="yes"
  health="WARN"
  problems+=("外网出口延迟偏高：$exit_latency")
fi
if is_number "$gateway_latency_ms" && [ "$gateway_latency_ms" -ge "$GATEWAY_LATENCY_WARN_MS" ]; then
  lan_slow="yes"
  health="WARN"
  problems+=("内网网关延迟偏高：$gateway_latency")
fi

if [ "$system_vpn_active" = "yes" ] && [ "$proxy_label" != "none" ]; then
  if [ "$active_tunnel_route_mode" = "全局默认路由" ]; then
    status_line="🛡️🛰️ 全局VPN+代理"
  elif [ "$active_tunnel_route_mode" = "分流隧道" ]; then
    status_line="🧩🛰️ 分流VPN+代理"
  else
    status_line="🔌🛰️ VPN接口+代理"
  fi
elif [ "$system_vpn_active" = "yes" ]; then
  if [ "$active_tunnel_route_mode" = "全局默认路由" ]; then
    status_line="🛡️ 全局VPN"
  elif [ "$active_tunnel_route_mode" = "分流隧道" ]; then
    status_line="🧩 分流VPN"
  else
    status_line="🔌 VPN接口"
  fi
elif [ "$proxy_label" != "none" ]; then
  status_line="🛰️ 代理${PROXY_PORT}"
else
  status_line="🏠 本地连接"
fi

if [ "$public_ip" = "-" ]; then
  health="WARN"
  problems+=("出口 IP 获取失败")
fi

external_mark="✅"
if [ "$public_ip" = "-" ] || [ "$external_slow" = "yes" ]; then
  external_mark="⚠️"
fi

vpn_mark="⚪"
if [ "$system_vpn_active" = "yes" ] || [ "$proxy_label" != "none" ]; then
  vpn_mark="✅"
fi

lan_mark="✅"
if [ "$dns_servers" = "-" ] || [ "$gateway" = "-" ] || [ "$iface" = "-" ] || [ "$lan_slow" = "yes" ]; then
  lan_mark="⚠️"
fi

connection_mode="本地直连 / 无 VPN"
connection_note=""
if [ "$system_vpn_active" = "yes" ] && [ "$proxy_label" != "none" ]; then
  connection_mode="双层：${active_tunnel_route_mode} + 本地代理"
  connection_note="双层链路可能增加延迟"
elif [ "$system_vpn_active" = "yes" ]; then
  connection_mode="单层：${active_tunnel_route_mode}"
elif [ "$proxy_label" != "none" ]; then
  connection_mode="单层：仅本地代理"
fi

echo "$status_line"
echo "---"
if [ "$health" = "OK" ]; then
  echo "✅ 网络拓扑正常    🔄 刷新 | refresh=true"
else
  echo "⚠️ 网络拓扑异常    🔄 刷新 | refresh=true"
fi
echo "---"
echo "${external_mark} 外网情况"
if [ "$public_ip" != "-" ]; then
  echo "↳ ✅ 出口  $public_ip  $public_flag $public_country_label / $public_city  ⏱️ $exit_latency"
else
  echo "↳ ⚠️ 出口  -  ⏱️ $exit_latency"
fi
if [ "$public_org" = "Cloudflare trace" ]; then
  echo "  • 🔎 检测源  Cloudflare trace"
elif [ "$public_org" != "-" ]; then
  echo "  • 🏢 运营商  $public_org"
fi
echo "---"
echo "${vpn_mark} VPN / 代理"
echo "↳ 🧭 当前  $connection_mode"
if [ -n "$connection_note" ]; then
  echo "↳ ℹ️ $connection_note"
fi
if [ "$system_vpn_active" = "yes" ]; then
  i=1
  while [ $i -le ${#tunnel_ifaces[@]} ]; do
    echo "↳ ✅ 系统 VPN  ${tunnel_names[$i]}  ${tunnel_ifaces[$i]} / ${tunnel_ips[$i]}"
    if [ "${tunnel_ifaces[$i]}" = "$active_tunnel_iface" ]; then
      echo "   $active_tunnel_route_mode / ${active_tunnel_route_count} 路由 · ↓ $(format_activity_rate "$warp_rate_down") ↑ $(format_activity_rate "$warp_rate_up")"
    fi
    if [ "${tunnel_names[$i]}" = "Cloudflare WARP" ]; then
      echo "   ${warp_protocol:-"-"} · ${warp_org:-"-"}"
    fi
    i=$((i + 1))
  done
else
  echo "↳ ⚪ 系统 VPN  未检测到"
fi
if [ "$proxy_label" != "none" ]; then
  if [ "$proxy_app" != "-" ] && [ "$proxy_app" != "未知代理软件" ]; then
    echo "↳ ✅ 本地代理  $proxy_app  $proxy_label"
  else
    echo "↳ ✅ 本地代理  $proxy_label"
  fi
else
  echo "↳ ⚪ 本地代理  未启用"
fi
if [ "$proxy_process" != "-" ]; then
  echo "   核心 $proxy_process · ↓ $(format_activity_rate "$proxy_rate_down") ↑ $(format_activity_rate "$proxy_rate_up")"
fi
echo "---"
echo "${lan_mark} 内网情况"
echo "↳ ✅ DNS  $dns_servers"
echo "↳ 🏠 网关  $gateway / $iface  ⏱️ $gateway_latency"
echo "↳ 📈 Wi‑Fi  ↓ $(format_activity_rate "$en0_rate_down")   ↑ $(format_activity_rate "$en0_rate_up")"
if [ ${#problems[@]} -gt 0 ]; then
  echo "---"
  echo "⚠️ 问题"
  for problem in "${problems[@]}"; do
    echo "↳ $problem"
  done
fi
