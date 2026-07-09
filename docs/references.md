# References

This document collects external projects that are useful references for the Network Baseline Monitor direction.

The goal is not to copy these projects.

The goal is to learn from their design, detection logic, output style, and product boundaries.

---

## 1. LinXiaoTao/FuckClaude

Repository:

https://github.com/LinXiaoTao/FuckClaude

### What it does

FuckClaude is a browser-based environment signal scanner.

It checks browser-visible and OS-related signals such as:

- System timezone
- Browser language
- Chinese fonts
- Chinese vendor fonts
- Chinese browser / WebView
- Chinese-brand device
- Intl locale
- Timezone offset
- Emoji rendering style

### What we can learn

- Clear signal-based detection
- Each detection item has a name, weight, and explanation
- Local-first browser detection
- User-friendly scan result
- Good result explanation style

### What we should not copy

- Do not copy the risk scoring model
- Do not claim to predict account restrictions
- Do not focus v0.1 on browser fingerprinting
- Do not turn this project into a Claude-specific risk checker

### Relevance to this project

Useful for future browser consistency checks.

Not part of v0.1.

---

## 2. orhun/dnsleaktest-tui

Repository:

https://github.com/orhun/dnsleaktest-tui

### What it does

A terminal UI tool for DNS leak testing.

### What we can learn

- DNS leak detection workflow
- Clear terminal output
- Separating detection logic from display logic
- Showing DNS result in a simple and understandable way

### What we should not copy

- Do not build a full TUI in v0.1
- Do not overcomplicate the user interface
- Do not make DNS leak testing the only feature

### Relevance to this project

Highly relevant to the DNS part of Network Baseline Monitor.

v0.1 should include DNS resolver detection and drift comparison.

---

## 3. passteque/gluetun

Repository:

https://github.com/passteque/gluetun

### What it does

A Docker-based VPN client container designed to control and route network traffic through a VPN tunnel.

### What we can learn

- Network exit health check
- VPN tunnel state monitoring
- Docker-based network isolation ideas
- Practical network reliability thinking

### What we should not copy

- Do not turn v0.1 into a VPN container
- Do not manage VPN connections directly
- Do not require Docker for v0.1
- Do not become a proxy/VPN tool

### Relevance to this project

Useful for future Docker or AI agent sandbox network checks.

Not required in v0.1.

---

## 4. fingerprintjs/fingerprintjs

Repository:

https://github.com/fingerprintjs/fingerprintjs

### What it does

A browser fingerprinting library that collects and normalizes multiple browser signals.

### What we can learn

- Signal collection design
- Signal normalization
- Environment fingerprint concepts
- How to structure multiple detectors cleanly

### What we should not copy

- Do not implement browser fingerprinting in v0.1
- Do not use fingerprinting for tracking users
- Do not build an anti-detection tool
- Do not make browser identity the first milestone

### Relevance to this project

Useful for future Browser Consistency Monitor.

Not part of the first milestone.

---

## 5. doug-leith/appFirewall

Repository:

https://github.com/doug-leith/appFirewall

### What it does

A macOS application firewall / network monitoring project.

### What we can learn

- macOS network observation
- Application-level outbound connection monitoring
- Local network visibility
- Security-focused UX

### What we should not copy

- Do not build an application firewall in v0.1
- Do not require kernel/network extension permissions
- Do not monitor every app connection yet
- Do not add complex allow/block rules

### Relevance to this project

Useful for a future phase:

- Claude Code outbound connection visibility
- Cursor outbound connection visibility
- AI tool network activity monitoring

Not part of v0.1.

---

## 6. Little Snitch / Portmaster-style tools

### What they do

These tools focus on observing and controlling outbound network connections.

### What we can learn

- Continuous network visibility
- Simple status indicator
- Detailed view only when needed
- Application-level network awareness

### What we should not copy

- Do not build a full firewall
- Do not build a complex rule engine
- Do not require users to manage hundreds of rules
- Do not make v0.1 heavy

### Relevance to this project

Useful for long-term product thinking.

Not part of the first version.

---

# What We Actually Build First

After reviewing the references, v0.1 remains intentionally small.

## v0.1: Network Baseline Monitor

The first version only answers one question:

> Has my current network environment drifted from my trusted baseline?

## Included in v0.1

- Public IPv4
- Country / region
- ASN / ISP
- DNS resolver
- IPv6 availability
- Trusted baseline
- Drift comparison
- SwiftBar status output

## Not included in v0.1

- Browser fingerprint
- Docker isolation
- Claude Code inspection
- MCP permission checks
- API key scanning
- IP reputation score
- Account risk prediction
- Anti-fraud or anti-ban logic
- VPN/proxy management

---

# Product Principle

This project should tell facts, not make promises.

Good output:

```text
ASN changed
DNS changed
IPv6 enabled
```

Bad output:

```text
This environment is safe.
This account will not be restricted.
This IP is clean.
```

The project should stay small, local-first, and verifiable.
