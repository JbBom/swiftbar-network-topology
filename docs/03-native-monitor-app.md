# Native Monitor App

## Purpose

Build a native macOS menu bar application that presents the existing Network
Baseline Monitor and AI Environment Guard data as a focused, card-based panel.

The native app is a new presentation layer. It does not replace the stable
SwiftBar plugin or reimplement the monitoring rules.

## Preserved Baseline

The stable SwiftBar release is preserved by the Git tag:

```text
swiftbar-plugin-v1.0
```

The native app is developed only on the `feat/swiftui-monitor-app` branch until
it reaches a separately reviewed release milestone.

## Product Goal

The first view should answer three questions immediately:

1. Is the AI environment ready, needs confirmation, or needs action?
2. Is the trusted network baseline stable?
3. Has the local system configuration changed from its trusted baseline?

The panel should show concise detail only after these states are visible.

## Architecture

```text
Existing shell collectors
  NBM / AEG / system baseline
            |
            v
Structured local snapshot adapter
            |
            v
SwiftUI menu bar app
  status header / cards / actions / report export
```

The structured adapter is required before the app reads complex topology data.
The app must not scrape SwiftBar menu text as its long-term data source.

## Milestone 1: Native Shell

- SwiftUI macOS menu bar app target
- Compact menu bar icon with ready/caution/alert/unknown state colors
- Window-style panel with AI environment, system consistency, and network
  baseline cards
- Refresh action and report export action
- Read-only integration with current AEG and system commands

## Milestone 2: Structured Network Detail

- Local JSON snapshot for public egress, latency, VPN/proxy and LAN status
- Header with country/city and latency
- Dedicated cards for external network, VPN/proxy and LAN
- No parsing of human-readable SwiftBar output

## Milestone 3: Native Interaction

- User-confirmed network baseline update
- User-confirmed system baseline update
- Open exported report directory
- Local history view

## Safety Boundaries

- No proxy switching, VPN switching, or process termination.
- No browser fingerprint masking or platform-control bypass.
- No account-risk score or claim that a green state prevents restrictions.
- Baseline updates remain user-confirmed.

## Acceptance Criteria for Milestone 1

- Builds with the installed Xcode/Swift toolchain.
- Shows current AEG and system baseline states from local helpers.
- Refresh does not modify baselines, network settings, or AI processes.
- The existing SwiftBar plugin remains unchanged and usable.
