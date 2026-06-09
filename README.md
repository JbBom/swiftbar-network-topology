# SwiftBar Network Topology / macOS 网络拓扑监控

A SwiftBar plugin for monitoring macOS network topology: public egress, VPN tunnel mode, local proxy, DNS, gateway, latency, and live traffic rates.

一个用于 SwiftBar 的 macOS 菜单栏网络拓扑监控插件：快速查看外网出口、VPN 路由模式、本地代理、DNS、网关、延迟和实时速率。

It is designed for people who often run a mix of VPN clients, Cloudflare WARP, corporate VPN, Clash/v2rayN/sing-box style local proxies, and want to quickly answer:

- Am I using local network, proxy, VPN, or both?
- Is the VPN a global default route or only a split tunnel?
- Which proxy app and core process are serving my local proxy port?
- What is my current public egress country, IP, and latency?
- Are DNS, gateway, and Wi-Fi link status normal?

## Preview

```text
🧩🧦 分流VPN+代理
---
✅ 网络拓扑正常    🔄 刷新
---
✅ 外网情况
↳ ✅ 出口  104.28.x.x  🇸🇬 新加坡 SG / Singapore  ⏱️ 1200 ms
  • 🏢 运营商  AS13335 Cloudflare, Inc.
---
✅ VPN / 代理
↳ 🧭 当前  双层：分流隧道 + 本地代理
↳ ✅ 系统 VPN  aTrust  utun7 / 10.0.0.2
   分流隧道 / 40 路由 · ↓ 空闲 ↑ 空闲
↳ ✅ 本地代理  v2rayN  127.0.0.1:10808
   核心 xray · ↓ 34.5 KB/s ↑ 35.0 KB/s
---
✅ 内网情况
↳ ✅ DNS  192.168.1.1
↳ 🏠 网关  192.168.1.1 / en0  ⏱️ 3 ms
↳ 📈 Wi-Fi  ↓ 27.6 KB/s ↑ 23.6 KB/s
```

The current plugin output is Chinese-first. English labels can be added later as a config option.

## Requirements

- macOS
- [SwiftBar](https://swiftbar.app/)
- zsh, curl, ping, ifconfig, route, scutil, netstat, lsof, nettop
- Optional: `ipinfo` CLI for richer public IP metadata
- Optional: `warp-cli` for Cloudflare WARP details

Most required command line tools are already included with macOS.

## Install

1. Install SwiftBar.
2. Copy `network-topology.10s.sh` into your SwiftBar plugin folder.
3. Make it executable:

```sh
chmod +x ~/SwiftBarPlugins/network-topology.10s.sh
```

4. Refresh SwiftBar.

You can also run:

```sh
./install.sh ~/SwiftBarPlugins
```

## Configuration

The plugin can be configured with environment variables:

```sh
PROXY_PORT=10808
EXTERNAL_LATENCY_WARN_MS=3000
GATEWAY_LATENCY_WARN_MS=80
```

SwiftBar runs plugin scripts directly. If you need custom values, edit the top of `network-topology.10s.sh` or export variables in the shell environment used by SwiftBar.

## What It Detects

- Public egress IP, country, city/colo, provider, latency
- System VPN tunnel interfaces: `utun`, `tun`, `tap`, `ppp`
- VPN route mode:
  - global default route
  - split tunnel
  - interface only
- Known VPN/proxy apps when possible:
  - Cloudflare WARP
  - aTrust
  - Surge
  - Clash / Mihomo
  - sing-box
  - WireGuard
  - OpenVPN
  - v2rayN
- Local proxy listener and parent app, such as `v2rayN -> xray -> 10808`
- DNS servers
- Default gateway
- Wi-Fi and tunnel traffic rates

## Roadmap

- Configurable Chinese/English labels
- Faster refresh with cached external checks
- Exportable diagnostic report
- Native macOS floating desktop monitor using the same detection logic

## Notes

- The plugin is read-only. It does not change network settings.
- Public IP lookup uses `ipinfo` when available and falls back to `ipinfo.io/json` or Cloudflare trace.
- Some VPN clients create inactive `utun` interfaces. The plugin only treats a tunnel as active when it has a real tunnel IP.
- macOS and SwiftBar may compress whitespace in menu items. The plugin uses visible hierarchy markers like `↳` and `•`.

## Privacy

The plugin displays local network and public egress information in your menu bar. It does not upload data except for public IP and latency checks against public endpoints such as ipinfo.io and Cloudflare trace.

Before sharing screenshots, consider masking:

- public IP address
- internal IP and gateway
- organization or team names
- VPN provider or corporate VPN identifiers

## License

MIT
