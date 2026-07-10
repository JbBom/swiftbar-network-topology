# Roadmap

## AI Environment Guard

### Phase 1: Framework

- [x] AI application process profiles
- [x] Read-only process detection
- [x] Readiness state machine
- [x] Change-only JSONL event history
- [x] Isolated regression tests

### Phase 2: SwiftBar Alerts

- [x] Show AI readiness and running applications
- [x] Record assessments during refresh
- [x] Notify once when entering alert
- [ ] Send a macOS notification on transitions into alert
- [ ] Show recovery actions

### Phase 3: Preflight and Profiles

- [ ] One-command preflight before launching an AI CLI
- [ ] Per-application trusted environment profiles
- [ ] System timezone, locale and endpoint consistency
- [ ] Browser consistency as a separate optional module

## SwiftBar Plugin

- Add language switch for Chinese and English labels.
- Add cached public IP and latency checks to reduce menu refresh delay.
- Add a one-click diagnostic report output.
- Improve app detection for more VPN and proxy clients.

## Desktop Monitor

The next major direction is a native macOS floating monitor.

Planned shape:

```text
🧩🧦 分流VPN+代理
外网  新加坡 SG  104.28.x.x  1.2s
VPN   aTrust  分流 40 路由
代理  v2rayN / xray / 10808
内网  DNS OK / 网关 3ms
```

Possible implementation:

- SwiftUI menu bar app
- transparent floating panel
- same shell detection engine as the SwiftBar plugin
- optional compact and detailed modes
