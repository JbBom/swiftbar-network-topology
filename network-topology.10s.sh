#!/bin/zsh

# SwiftBar plugin: read-only network topology monitor.
# Filename interval ".10s" makes SwiftBar refresh every 10 seconds.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 可调参数：SwiftBar 每 10 秒刷新一次，但外网 IP 查询默认缓存 30 秒，避免菜单栏卡顿。
PROXY_PORT="${PROXY_PORT:-10808}"
PROXY_PORTS="${PROXY_PORTS:-$PROXY_PORT 7890 7897 6152 20170}"
PUBLIC_PROBE_CACHE_SECONDS="${PUBLIC_PROBE_CACHE_SECONDS:-30}"
EXTERNAL_LATENCY_WARN_MS="${EXTERNAL_LATENCY_WARN_MS:-3000}"
GATEWAY_LATENCY_WARN_MS="${GATEWAY_LATENCY_WARN_MS:-80}"
CACHE_DIR="${TMPDIR:-/tmp}/network-topology-${USER}"
mkdir -p "$CACHE_DIR" 2>/dev/null

safe_run() {
  "$@" 2>/dev/null
}

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

dns_list_to_json() {
  local value="$1"
  if [ -z "$value" ] || [ "$value" = "-" ]; then
    echo "[]"
    return
  fi
  printf '%s\n' "$value" | sed 's/[[:space:]]*,[[:space:]]*/","/g; s/^/["/; s/$/"]/'
}

first_nonempty() {
  local v
  for v in "$@"; do
    if [ -n "$v" ] && [ "$v" != "none" ] && [ "$v" != "-" ]; then
      echo "$v"
      return
    fi
  done
  echo ""
}

# 轻量 JSON 字段提取：优先 jq，没有 jq 时用 sed 兜底。
json_val() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
  fi
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
  # macOS netstat -ibn 字段在不同系统版本上略有差异；这里优先取 <Link#...> 行的 Ibytes / Obytes。
  netstat -ibn 2>/dev/null | awk -v ifc="$ifc" '
    $1 == ifc && $0 ~ /<Link/ {
      # 常见 macOS: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
      if (NF >= 10) { print $(NF-4), $(NF-1); exit }
    }'
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

expected_country_from_name() {
  local name="$1"
  local upper
  local tokens
  upper="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
  case "$upper" in
    *香港*|*HONG*KONG*) echo "HK"; return ;;
    *新加坡*|*SINGAPORE*) echo "SG"; return ;;
    *日本*|*JAPAN*) echo "JP"; return ;;
    *美国*|*UNITED*STATES*|*USA*) echo "US"; return ;;
    *台湾*|*TAIWAN*) echo "TW"; return ;;
    *韩国*|*KOREA*) echo "KR"; return ;;
    *英国*|*UNITED*KINGDOM*) echo "GB"; return ;;
    *德国*|*GERMANY*) echo "DE"; return ;;
    *法国*|*FRANCE*) echo "FR"; return ;;
    *加拿大*|*CANADA*) echo "CA"; return ;;
    *澳大利亚*|*AUSTRALIA*) echo "AU"; return ;;
    *荷兰*|*NETHERLANDS*) echo "NL"; return ;;
  esac
  tokens="$(echo "$upper" | sed 's/[^A-Z0-9]/ /g')"
  for code in HK SG JP US TW KR GB UK DE FR CA AU NL; do
    if echo " $tokens " | grep -q " $code "; then
      if [ "$code" = "UK" ]; then
        echo "GB"
      else
        echo "$code"
      fi
      return
    fi
  done
  echo "-"
}

v2rayn_active_entry() {
  local config="$HOME/Library/Application Support/v2rayN/guiConfigs/guiNConfig.json"
  local db="$HOME/Library/Application Support/v2rayN/guiConfigs/guiNDB.db"
  local index_id
  if [ ! -f "$config" ] || [ ! -f "$db" ] || ! command -v sqlite3 >/dev/null 2>&1; then
    echo "-|-|-"
    return
  fi
  index_id="$(sed -n 's/.*"IndexId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -n 1 | trim)"
  if [ -z "$index_id" ]; then
    echo "-|-|-"
    return
  fi
  index_id="$(printf "%s" "$index_id" | sed "s/'/''/g")"
  sqlite3 -separator '|' "$db" "select coalesce(Remarks,'-'), coalesce(Address,'-'), coalesce(Port,'-') from ProfileItem where IndexId='$index_id' limit 1;" 2>/dev/null
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

normalize_proxy_url() {
  local proxy="$1"
  if [ -z "$proxy" ] || [ "$proxy" = "none" ] || [ "$proxy" = "-" ]; then
    echo ""
  elif echo "$proxy" | grep -q "://"; then
    echo "$proxy"
  else
    echo "http://$proxy"
  fi
}

fetch_url() {
  local proxy="$1"
  local url="$2"
  if [ -n "$proxy" ]; then
    curl --proxy "$proxy" --connect-timeout 1.5 -L -m 3 -s "$url" 2>/dev/null
  else
    curl --connect-timeout 1.5 -L -m 3 -s "$url" 2>/dev/null
  fi
}

probe_ipinfo() {
  local proxy="$1"
  local body
  body="$(fetch_url "$proxy" "https://ipinfo.io/json")"
  local ip city country org
  ip="$(echo "$body" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  city="$(echo "$body" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  country="$(echo "$body" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  org="$(echo "$body" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  if [ -n "$ip" ] && [ -n "$country" ]; then
    echo "$ip|$country|${city:-"-"}|${org:-"-"}|ipinfo.io|-"
  fi
}

probe_ipwho() {
  local proxy="$1"
  local expected_ip="$2"
  local body ip city country asn org
  body="$(fetch_url "$proxy" "https://ipwho.is/$expected_ip")"
  ip="$(echo "$body" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  city="$(echo "$body" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  country="$(echo "$body" | sed -n 's/.*"country_code"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  asn="$(echo "$body" | sed -n 's/.*"asn"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1 | trim)"
  org="$(echo "$body" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  if [ "$ip" = "$expected_ip" ] && [ -n "$asn" ]; then
    echo "$ip|${country:-"-"}|${city:-"-"}|AS${asn} ${org:-unknown}|ipwho.is|-"
  fi
}

probe_myip() {
  local proxy="$1"
  local body
  body="$(fetch_url "$proxy" "https://api.myip.com")"
  local ip country
  ip="$(echo "$body" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  country="$(echo "$body" | sed -n 's/.*"cc"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | trim)"
  if [ -n "$ip" ] && [ -n "$country" ]; then
    echo "$ip|$country|-|-|MyIP.com|-"
  fi
}

probe_cloudflare() {
  local proxy="$1"
  local body
  if [ -n "$proxy" ]; then
    body="$(curl --proxy "$proxy" --connect-timeout 1.5 -L -m 3 -s -w '\n__time_total=%{time_total}' https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  else
    body="$(curl --connect-timeout 1.5 -L -m 3 -s -w '\n__time_total=%{time_total}' https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)"
  fi
  local ip country colo
  local timing latency
  ip="$(echo "$body" | awk -F= '$1 == "ip" {print $2; exit}' | trim)"
  country="$(echo "$body" | awk -F= '$1 == "loc" {print $2; exit}' | trim)"
  colo="$(echo "$body" | awk -F= '$1 == "colo" {print $2; exit}' | trim)"
  timing="$(echo "$body" | awk -F= '$1 == "__time_total" {print $2; exit}' | trim)"
  latency="-"
  if [ -n "$timing" ]; then
    latency="$(awk -v v="$timing" 'BEGIN {if (v > 0) printf "%.0f ms", v * 1000}')"
  fi
  if [ -n "$ip" ] && [ -n "$country" ]; then
    echo "$ip|$country|${colo:-"-"}|-|Cloudflare trace|$latency"
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

warp_connected="no"
if echo "$warp_status" | grep -Eqi "^Status update:[[:space:]]+Connected$"; then
  warp_connected="yes"
fi

warp_protocol="$(echo "$warp_settings" | awk -F': ' '/WARP tunnel protocol:/ {print $2; exit}' | trim)"
warp_org="$(echo "$warp_settings" | awk -F': ' '/Organization:/ {print $2; exit}' | trim)"

dns_servers="$(echo "$dns_state" | awk '/nameserver\[[0-9]+\] :/ {print $3}' | awk '!seen[$0]++' | paste -sd ',' - | sed 's/,/, /g')"
if [ -z "$dns_servers" ]; then
  dns_servers="-"
  health="WARN"
  problems+=("No DNS server detected")
fi

http_proxy=""
https_proxy=""
socks_proxy=""
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
for dev in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep '^utun'); do
  info="$(safe_run ifconfig "$dev")"
  if echo "$info" | grep -q "100\.96\.\|2606:4700:cf1"; then
    warp_iface="$dev"
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
rate_state="$CACHE_DIR/rate.state"
activity_iface="$iface"
if [ -z "$activity_iface" ] || [ "$activity_iface" = "-" ]; then
  activity_iface="en0"
fi
en0_bytes="$(iface_bytes "$activity_iface")"
warp_bytes="- -"
if [ "$active_tunnel_iface" != "-" ]; then
  warp_bytes="$(iface_bytes "$active_tunnel_iface")"
fi
proxy_port="-"
proxy_pid="-"
proxy_process="-"
for candidate_port in $PROXY_PORTS; do
  line="$(safe_run lsof -nP -iTCP:${candidate_port} -sTCP:LISTEN | awk 'NR == 2 {print; exit}')"
  if [ -n "$line" ]; then
    proxy_port="$candidate_port"
    proxy_process="$(echo "$line" | awk '{print $1; exit}' | trim)"
    proxy_pid="$(echo "$line" | awk '{print $2; exit}' | trim)"
    break
  fi
done
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
proxy_entry_name="-"
proxy_entry_host="-"
proxy_entry_port="-"
proxy_entry_expected_country="-"
proxy_entry_country_label="-"
if [ "$proxy_app" = "v2rayN" ]; then
  proxy_entry="$(v2rayn_active_entry)"
  proxy_entry_name="$(echo "$proxy_entry" | awk -F'|' '{print $1}')"
  proxy_entry_host="$(echo "$proxy_entry" | awk -F'|' '{print $2}')"
  proxy_entry_port="$(echo "$proxy_entry" | awk -F'|' '{print $3}')"
  proxy_entry_expected_country="$(expected_country_from_name "$proxy_entry_name")"
  if [ "$proxy_entry_expected_country" != "-" ]; then
    proxy_entry_country_label="$(country_flag "$proxy_entry_expected_country") $(country_cn "$proxy_entry_expected_country") $proxy_entry_expected_country"
  fi
fi
en0_in="$(echo "$en0_bytes" | awk '{print $1}')"
en0_out="$(echo "$en0_bytes" | awk '{print $2}')"
warp_in="$(echo "$warp_bytes" | awk '{print $1}')"
warp_out="$(echo "$warp_bytes" | awk '{print $2}')"

en0_rate_down="calibrating"
en0_rate_up="calibrating"
warp_rate_down="calibrating"
warp_rate_up="calibrating"

if [ -f "$rate_state" ]; then
  read -r prev_ts prev_en0_in prev_en0_out prev_warp_iface prev_warp_in prev_warp_out < "$rate_state"
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
  fi
fi
echo "$now_ts ${en0_in:-0} ${en0_out:-0} ${active_tunnel_iface:-"-"} ${warp_in:-0} ${warp_out:-0}" > "$rate_state"

public_ip="-"
public_city="-"
public_country_code="-"
public_flag="🏳️"
public_org="-"
public_asn="-"
public_source="-"
public_probe_summary="-"
public_latency="-"

public_lookup_proxy=""
if [ -n "$socks_proxy" ]; then
  public_lookup_proxy="$(normalize_proxy_url "socks5h://$socks_proxy")"
else
  public_lookup_proxy="$(normalize_proxy_url "$(first_nonempty "$https_proxy" "$http_proxy" "$env_proxy")")"
fi

probe_results=()
probe_cache_key="$(printf 'v2|%s' "$public_lookup_proxy" | cksum | awk '{print $1}')"
probe_cache_file="$CACHE_DIR/public-probe.${probe_cache_key}.cache"
probe_cache_fresh="no"
if [ -f "$probe_cache_file" ]; then
  cache_mtime="$(stat -f %m "$probe_cache_file" 2>/dev/null || stat -c %Y "$probe_cache_file" 2>/dev/null)"
  if is_number "$cache_mtime" && [ $((now_ts - cache_mtime)) -lt "$PUBLIC_PROBE_CACHE_SECONDS" ] 2>/dev/null; then
    probe_cache_fresh="yes"
  fi
fi
if [ "$probe_cache_fresh" = "yes" ]; then
  while IFS= read -r cached_probe; do
    if [ -n "$cached_probe" ]; then
      probe_results+=("$cached_probe")
    fi
  done < "$probe_cache_file"
else
  for probe_result in "$(probe_myip "$public_lookup_proxy")" "$(probe_cloudflare "$public_lookup_proxy")" "$(probe_ipinfo "$public_lookup_proxy")"; do
    if [ -n "$probe_result" ]; then
      probe_results+=("$probe_result")
    fi
  done
  if [ ${#probe_results[@]} -gt 0 ]; then
    printf '%s\n' "${probe_results[@]}" > "$probe_cache_file"
  fi
fi

if [ ${#probe_results[@]} -gt 0 ]; then
  chosen_probe="${probe_results[1]}"
  if [ -n "$public_lookup_proxy" ]; then
    for probe_result in "${probe_results[@]}"; do
      probe_country="$(echo "$probe_result" | awk -F'|' '{print toupper($2)}')"
      if [ "$probe_country" != "CN" ]; then
        chosen_probe="$probe_result"
        break
      fi
    done
  fi

  public_ip="$(echo "$chosen_probe" | awk -F'|' '{print $1}')"
  public_country_code="$(echo "$chosen_probe" | awk -F'|' '{print toupper($2)}')"
  public_city="$(echo "$chosen_probe" | awk -F'|' '{print $3}')"
  public_org="$(echo "$chosen_probe" | awk -F'|' '{print $4}')"
  public_source="$(echo "$chosen_probe" | awk -F'|' '{print $5}')"
  public_latency="$(echo "$chosen_probe" | awk -F'|' '{print $6}')"

  if [ -z "$public_org" ] || [ "$public_org" = "-" ]; then
    for probe_result in "${probe_results[@]}"; do
      probe_ip="$(echo "$probe_result" | awk -F'|' '{print $1}')"
      probe_org="$(echo "$probe_result" | awk -F'|' '{print $4}')"
      if [ "$probe_ip" = "$public_ip" ] && [ -n "$probe_org" ] && [ "$probe_org" != "-" ]; then
        public_org="$probe_org"
        break
      fi
    done
  fi

  # MyIP and Cloudflare provide the egress address but not ASN data. When
  # ipinfo is unavailable, enrich that same address once per cache interval.
  if { [ -z "$public_org" ] || [ "$public_org" = "-" ]; } && \
     [ "$public_ip" != "-" ] && [ "$probe_cache_fresh" != "yes" ]; then
    asn_probe="$(probe_ipwho "$public_lookup_proxy" "$public_ip")"
    if [ -n "$asn_probe" ]; then
      public_org="$(echo "$asn_probe" | awk -F'|' '{print $4}')"
      probe_results+=("$asn_probe")
      printf '%s\n' "${probe_results[@]}" > "$probe_cache_file"
    fi
  fi

  if [ -z "$public_city" ] || [ "$public_city" = "-" ]; then
    for probe_result in "${probe_results[@]}"; do
      probe_country="$(echo "$probe_result" | awk -F'|' '{print toupper($2)}')"
      probe_city="$(echo "$probe_result" | awk -F'|' '{print $3}')"
      if [ "$probe_country" = "$public_country_code" ] && [ -n "$probe_city" ] && [ "$probe_city" != "-" ]; then
        public_city="$probe_city"
        break
      fi
    done
  fi
  if [ -z "$public_latency" ] || [ "$public_latency" = "-" ]; then
    for probe_result in "${probe_results[@]}"; do
      probe_latency="$(echo "$probe_result" | awk -F'|' '{print $6}')"
      if [ -n "$probe_latency" ] && [ "$probe_latency" != "-" ]; then
        public_latency="$probe_latency"
        break
      fi
    done
  fi

  public_probe_summary="$(printf '%s\n' "${probe_results[@]}" | awk -F'|' '{printf "%s=%s/%s ", $5, toupper($2), $1}' | trim)"
  probe_country_count="$(printf '%s\n' "${probe_results[@]}" | awk -F'|' 'NF >= 2 && $2 != "" {seen[toupper($2)] = 1} END {for (c in seen) count++; print count + 0}')"
  if [ "$probe_country_count" -gt 1 ] 2>/dev/null; then
    health="WARN"
    problems+=("出口检测源不一致：$public_probe_summary")
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
public_asn="$(echo "$public_org" | sed -n 's/^\(AS[0-9][0-9]*\).*/\1/p')"
if [ -z "$public_asn" ]; then
  public_asn="-"
fi
if [ -z "$public_source" ]; then
  public_source="-"
fi
public_location="$public_country_label"
if [ "$public_city" != "-" ]; then
  public_location="$public_location / $public_city"
fi

proxy_label="none"
if [ "$system_proxy" = "enabled" ]; then
  proxy_label="$(first_nonempty "$socks_proxy" "$https_proxy" "$http_proxy" "enabled")"
elif [ "$env_proxy" != "none" ]; then
  proxy_label="$env_proxy"
elif [ "$proxy_port" != "-" ]; then
  proxy_label="127.0.0.1:$proxy_port（监听中，系统未开启）"
fi

gateway_latency="$(ping_latency "$gateway")"
if [ -z "$gateway_latency" ]; then
  gateway_latency="-"
fi

exit_latency="$public_latency"
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

if [ "$public_ip" != "-" ] && [ "$public_country_code" != "-" ]; then
  status_latency=""
  if [ "$exit_latency" != "-" ]; then
    status_latency="（$exit_latency）"
  fi
  status_line="$public_flag $public_country_name$status_latency"
else
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
    status_line="🛰️ 代理${proxy_port}"
  else
    status_line="🏠 本地连接"
  fi
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

# --- Network Baseline Monitor status --------------------------------
nbm_current_ip="$public_ip"
nbm_current_country="$public_country_code"
nbm_current_asn="$public_asn"
for field_name in nbm_current_ip nbm_current_country nbm_current_asn; do
  if [ "${(P)field_name}" = "-" ] || [ -z "${(P)field_name}" ]; then
    typeset "$field_name=null"
  fi
done
nbm_current_dns="$(dns_list_to_json "$dns_servers")"
nbm_current_ipv6="false"
if ifconfig -l 2>/dev/null | tr ' ' '\n' | while read -r dev; do
  [ -z "$dev" ] && continue
  ifconfig "$dev" 2>/dev/null | grep -q 'inet6 .*[^f][^e]80:' && exit 0
done; then
  nbm_current_ipv6="true"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NBM_HELPER_DIR="${NBM_HELPER_DIR:-$SCRIPT_DIR/scripts}"
if [ ! -f "$NBM_HELPER_DIR/nbm-check.sh" ]; then
  NBM_HELPER_DIR="$HOME/.nbm/bin"
fi
baseline_label="⚪ 网络基线：功能不可用"
baseline_detail=""
baseline_action_label="🔐 设为当前可信基线"
aeg_label="⚪ AI 环境：功能不可用"
aeg_status="unavailable"
aeg_running_apps=""
aeg_reason=""
aeg_action=""
system_label="⚪ 系统一致性：功能不可用"
system_detail=""
baseline_json='{"status":"error","error":"baseline check unavailable"}'
if [ -f "$NBM_HELPER_DIR/nbm-check.sh" ]; then
  baseline_json="$(
    NBM_CURRENT_STATE_READY=1 \
    NBM_CURRENT_PUBLIC_IPV4="$nbm_current_ip" \
    NBM_CURRENT_COUNTRY="$nbm_current_country" \
    NBM_CURRENT_ASN="$nbm_current_asn" \
    NBM_CURRENT_DNS_RESOLVER="$nbm_current_dns" \
    NBM_CURRENT_IPV6_AVAILABLE="$nbm_current_ipv6" \
      /bin/zsh "$NBM_HELPER_DIR/nbm-check.sh" --json --current-env 2>/dev/null
  )"
  baseline_rc=$?
  case $baseline_rc in
    0)
      baseline_label="🟢 网络基线：稳定"
      baseline_action_label="🔐 更新可信基线"
      ;;
    1)
      baseline_label="🟡 网络基线：发生漂移"
      baseline_output="$(
        NBM_CURRENT_STATE_READY=1 \
        NBM_CURRENT_PUBLIC_IPV4="$nbm_current_ip" \
        NBM_CURRENT_COUNTRY="$nbm_current_country" \
        NBM_CURRENT_ASN="$nbm_current_asn" \
        NBM_CURRENT_DNS_RESOLVER="$nbm_current_dns" \
        NBM_CURRENT_IPV6_AVAILABLE="$nbm_current_ipv6" \
          /bin/zsh "$NBM_HELPER_DIR/nbm-check.sh" --human --current-env 2>/dev/null
      )"
      baseline_detail="$(printf '%s\n' "$baseline_output" | sed -n \
        -e 's/^  public_ipv4:/↳ 公网 IPv4:/p' \
        -e 's/^  country:/↳ 国家\/地区:/p' \
        -e 's/^  asn:/↳ ASN:/p' \
        -e 's/^  dns_resolver:/↳ DNS:/p' \
        -e 's/^  ipv6_available:/↳ IPv6:/p' | sed 's/ -> / → /g')"
      baseline_action_label="🔐 更新可信基线"
      ;;
    2)
      baseline_error="$(printf '%s' "$baseline_json" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      if [ "$baseline_error" = "no baseline found" ]; then
        baseline_label="⚪ 网络基线：未建立"
      elif [ "$baseline_error" = "current state environment incomplete" ]; then
        baseline_label="⚪ 网络基线：当前信息不完整"
      else
        baseline_label="⚪ 网络基线：功能不可用"
      fi
      ;;
  esac
fi

if [ -f "$NBM_HELPER_DIR/aeg-assess.sh" ]; then
  aeg_output="$(
    /bin/zsh "$NBM_HELPER_DIR/aeg-assess.sh" \
      --json --record --notify-on-alert --network-json "$baseline_json" 2>/dev/null
  )"
  # The assessment JSON also contains network.status. Use the first status
  # field emitted by aeg-assess.sh instead of a greedy JSON-wide match.
  aeg_status="$(printf '%s' "$aeg_output" | awk -F'"status":"' 'NF > 1 { split($2, value, "\""); print value[1]; exit }')"
  aeg_running_apps="$(printf '%s' "$aeg_output" | grep -o '"label":"[^"]*"' | sed 's/^"label":"//; s/"$//' | paste -sd '、' -)"
  aeg_reason="$(printf '%s' "$aeg_output" | sed -n 's/.*"reasons":\[{"code":"[^"]*","message":"\([^"]*\)"}.*/\1/p' | head -1)"
  aeg_action="$(printf '%s' "$aeg_output" | sed -n 's/.*"actions":\[{"code":"[^"]*","message":"\([^"]*\)"}.*/\1/p' | head -1)"
  case "$aeg_status" in
    ready) aeg_label="🟢 AI 环境：可以运行" ;;
    caution) aeg_label="🟡 AI 环境：需要确认" ;;
    alert) aeg_label="🚨 AI 环境：请处理" ;;
    unknown) aeg_label="⚪ AI 环境：无法判断" ;;
  esac
fi

if [ -f "$NBM_HELPER_DIR/aeg-system.sh" ]; then
  system_output="$(/bin/zsh "$NBM_HELPER_DIR/aeg-system.sh" check --json 2>/dev/null)"
  system_rc=$?
  case "$system_rc" in
    0) system_label="🟢 系统一致性：稳定" ;;
    1)
      system_label="🟡 系统一致性：发生变化"
      system_detail="$(/bin/zsh "$NBM_HELPER_DIR/aeg-system.sh" check --human 2>/dev/null | sed -n \
        -e 's/^  os_version:/↳ macOS:/p' \
        -e 's/^  architecture:/↳ 架构:/p' \
        -e 's/^  timezone:/↳ 时区:/p' \
        -e 's/^  locale:/↳ 语言地区:/p' \
        -e 's/^  primary_interface:/↳ 默认网卡:/p' \
        -e 's/^  system_proxy_enabled:/↳ 系统代理:/p' | sed 's/ -> / → /g')"
      ;;
    2)
      system_error="$(printf '%s' "$system_output" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      if [ "$system_error" = "no system baseline found" ]; then
        system_label="⚪ 系统一致性：未建立"
      fi
      ;;
  esac
fi

menubar_status_icon="⚪"
case "$aeg_status" in
  ready) menubar_status_icon="🟢" ;;
  caution) menubar_status_icon="🟡" ;;
  alert) menubar_status_icon="🚨" ;;
esac
status_line="${menubar_status_icon}${status_line}"

echo "$status_line"
echo "---"
echo "$aeg_label"
if [ -n "$aeg_running_apps" ]; then
  echo "↳ 运行中的 AI：$aeg_running_apps"
else
  echo "↳ 运行中的 AI：未检测到"
fi
if [ "$aeg_status" = "caution" ] || [ "$aeg_status" = "alert" ] || [ "$aeg_status" = "unknown" ]; then
  [ -n "$aeg_reason" ] && echo "↳ 原因：$aeg_reason"
  [ -n "$aeg_action" ] && echo "↳ 建议：$aeg_action"
fi
echo "$system_label"
if [ -n "$system_detail" ]; then
  printf '%s\n' "$system_detail"
fi
echo "---"
echo "$baseline_label"
if [ -n "$baseline_detail" ]; then
  printf '%s\n' "$baseline_detail"
fi
if [ -f "$NBM_HELPER_DIR/nbm-trust.sh" ]; then
  echo "$baseline_action_label | bash=\"/bin/zsh\" param1=\"$NBM_HELPER_DIR/nbm-trust.sh\" param2=--force terminal=true refresh=true"
fi
if [ "$health" = "OK" ]; then
  echo "✅ 网络拓扑正常    🔄 刷新 | refresh=true"
else
  echo "⚠️ 网络拓扑异常    🔄 刷新 | refresh=true"
fi
echo "---"
echo "${external_mark} 外网情况"
if [ "$public_ip" != "-" ]; then
  echo "↳ ✅ 出口  $public_ip  $public_flag $public_location  ⏱️ $exit_latency"
else
  echo "↳ ⚠️ 出口  -  ⏱️ $exit_latency"
fi
if [ "$public_source" != "-" ]; then
  if [ "$probe_cache_fresh" = "yes" ]; then
    echo "  • 🔎 检测源  $public_source（缓存）"
  else
    echo "  • 🔎 检测源  $public_source"
  fi
fi
if [ "$public_org" != "-" ]; then
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
  echo "   代理核心  $proxy_process · 运行中"
fi
if [ "$proxy_entry_host" != "-" ] && [ "$proxy_entry_port" != "-" ]; then
  if [ "$proxy_entry_country_label" != "-" ]; then
    echo "   节点入口  $proxy_entry_country_label · $proxy_entry_name"
    echo "   入口地址  $proxy_entry_host:$proxy_entry_port"
  else
    echo "   节点入口  $proxy_entry_name · $proxy_entry_host:$proxy_entry_port"
  fi
  if [ "$proxy_entry_expected_country" != "-" ] && [ "$public_country_code" != "-" ] && [ "$proxy_entry_expected_country" != "$public_country_code" ]; then
    echo "   提示  节点入口像 $(country_cn "$proxy_entry_expected_country")，但实际出口是 $public_country_label"
  fi
fi
echo "---"
echo "${lan_mark} 内网情况"
echo "↳ ✅ DNS  $dns_servers"
echo "↳ 🏠 网关  $gateway / $iface  ⏱️ $gateway_latency"
echo "↳ 📈 活动网卡 $activity_iface  ↓ $(format_activity_rate "$en0_rate_down")   ↑ $(format_activity_rate "$en0_rate_up")"
if [ ${#problems[@]} -gt 0 ]; then
  echo "---"
  echo "⚠️ 问题"
  for problem in "${problems[@]}"; do
    echo "↳ $problem"
  done
fi
