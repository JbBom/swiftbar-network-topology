# Changelog

## Unreleased

- Reuse the SwiftBar plugin's current network state for baseline comparison.
- Cache ASN data with the existing public egress probes.
- Fix IPv6 boolean parsing on macOS.
- Fix concurrent temporary-file creation for check and trust actions.

## 0.1.1

- Fix public egress detection when macOS system proxy is enabled.
- Replace `ipinfo myip` CLI-first lookup with proxy-aware MyIP + Cloudflare trace checks.
- Warn when public egress detection sources disagree.
- Add v2rayN active node entry display for comparing node entry and actual egress.
- Remove slow `nettop` process-rate sampling to avoid SwiftBar refresh stalls.
- Remove unrelated Tailscale/WARP setting checks from topology health.
- Add configurable `PROXY_PORT`, `EXTERNAL_LATENCY_WARN_MS`, and `GATEWAY_LATENCY_WARN_MS`.

## 0.1.0

- Initial SwiftBar plugin release.
- Detect public egress IP, country, provider, and latency.
- Detect system VPN tunnel interfaces and route mode.
- Detect local proxy listener, parent proxy app, core process, and traffic rate.
- Detect DNS, gateway, and Wi-Fi traffic rate.
- Support visible hierarchy markers for SwiftBar menu readability.
