# SwiftBar Network Topology / macOS 网络拓扑监控

## Network Baseline Monitor Direction

This project is evolving from a macOS network topology monitor into a small network baseline and drift detection tool.

The first milestone is Network Baseline Monitor.

It does not predict account risk, bypass platform risk controls, or judge whether an IP is safe.

Its goal is simple:

> Detect whether the current network environment has drifted from a trusted baseline.

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
🇺🇸 美国（1300 ms）
---
✅ 网络拓扑正常    🔄 刷新
---
✅ 外网情况
↳ ✅ 出口  192.0.2.10  🇺🇸 美国 US / LAX  ⏱️ 1300 ms
  • 🔎 检测源  MyIP.com
---
✅ VPN / 代理
↳ 🧭 当前  单层：仅本地代理
↳ ⚪ 系统 VPN  未检测到
↳ ✅ 本地代理  v2rayN  127.0.0.1:10808
   代理核心  xray · 运行中
   节点入口  🇺🇸 美国 US · US
   入口地址  203.0.113.10:443
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
- zsh, curl, ping, ifconfig, route, scutil, netstat, lsof
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
- Proxy-aware public egress checks through the active macOS HTTP/HTTPS/SOCKS proxy
- Cross-checking with MyIP and Cloudflare trace, with warnings when sources disagree
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
- v2rayN active node entry, when available from the local v2rayN config/database
- DNS servers
- Default gateway
- Wi-Fi and tunnel traffic rates

## Roadmap

- Configurable Chinese/English labels
- Optional compact/verbose menu modes
- Exportable diagnostic report
- Native macOS floating desktop monitor using the same detection logic

## Notes

- The plugin is read-only. It does not change network settings.
- Public IP lookup is proxy-aware. When macOS system proxy is enabled, public egress checks are explicitly sent through that proxy.
- Public egress is checked with MyIP and Cloudflare trace. `ipinfo.io` is used only as a fallback when both primary checks fail.
- Some VPN clients create inactive `utun` interfaces. The plugin only treats a tunnel as active when it has a real tunnel IP.
- macOS and SwiftBar may compress whitespace in menu items. The plugin uses visible hierarchy markers like `↳` and `•`.

## Privacy

The plugin displays local network and public egress information in your menu bar. It does not upload data except for public IP and latency checks against public endpoints such as MyIP, Cloudflare trace, and fallback ipinfo.io.

Before sharing screenshots, consider masking:

- public IP address
- internal IP and gateway
- organization or team names
- VPN provider or corporate VPN identifiers

## License

MIT
