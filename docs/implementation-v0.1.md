# Implementation Plan: Network Baseline Monitor v0.1

This document breaks v0.1 into small, self-contained tasks. Each task should be small enough for an AI coding agent to implement in a single turn.

---

## Data Model

### Network Snapshot Structure

```json
{
  "public_ipv4": "203.0.113.10",
  "country": "US",
  "region": "California",
  "asn": "AS13335",
  "isp": "Cloudflare, Inc.",
  "dns_resolver": ["1.1.1.1", "1.0.0.1"],
  "ipv6_available": true,
  "trusted_at": "2026-07-09T14:30:00+08:00",
  "source": "myip.com"
}
```

Fields to detect drift on:

- `public_ipv4` — changed IP
- `country` — changed country
- `asn` — changed ISP/network
- `dns_resolver` — changed DNS
- `ipv6_available` — IPv6 on/off toggle

---

## Tasks

### Task 1: Define network snapshot data model

**File**: `scripts/nbm-snapshot.sh`

A source-able shell script that defines:

- `NBM_SNAPSHOT_FILE` — path to `~/.network-baseline/baseline.json`
- `nbm_snapshot_collect()` — collects current network state and outputs JSON to stdout
- `nbm_snapshot_save()` — saves JSON to `~/.network-baseline/baseline.json`
- `nbm_snapshot_load()` — reads JSON from the baseline file and outputs to stdout

**Acceptance**:

- `nbm_snapshot_collect` outputs valid JSON with all 6 fields
- `nbm_snapshot_save` creates the file and directory
- `nbm_snapshot_load` reads the file back

---

### Task 2: Implement baseline trust action

**File**: `scripts/nbm-trust.sh`

A script that:

- Calls `nbm_snapshot_collect` to get the current network state
- Asks user to confirm before saving (interactive or via `--yes` flag)
- Writes the snapshot to `~/.network-baseline/baseline.json`
- Prints a success message: `Baseline trusted and saved.`

**Acceptance**:

- `nbm-trust.sh --yes` saves baseline without prompt
- `nbm-trust.sh` asks for confirmation
- Saved file matches the snapshot schema

---

### Task 3: Implement drift check action

**File**: `scripts/nbm-check.sh`

A script that:

- Loads the trusted baseline from `~/.network-baseline/baseline.json`
- Collects the current network state
- Compares each drift field (IP, country, ASN, DNS, IPv6)
- Outputs result in two modes:
  - **Human-readable**: list changed fields with old → new values
  - **Machine**: JSON with `status` ("stable" or "drift") and `changes` array
- Exits with code 0 if stable, 1 if drift

**Acceptance**:

- `nbm-check.sh` returns 0 when nothing changed
- `nbm-check.sh` returns 1 when IP/ASN/DNS/IPv6 changed
- JSON output includes `status` and `changes` fields
- Human output shows old → new for each changed field

---

### Task 4: Integrate with SwiftBar

**File**: `network-topology.10s.sh` (modify existing)

Add a new section to the existing SwiftBar plugin:

- Add a menu separator and "Network Baseline" section header
- Show status:
  - 🟢 **Stable** if no drift (or no baseline exists yet)
  - 🟡 **Drift** if baseline has changed
- On click: show changed fields in submenu
- Add a "Trust Current" menu item that calls `nbm-trust.sh --yes`
- Add a "Check Now" menu item that calls `nbm-check.sh` and refreshes

**Design constraint**: the existing plugin must keep working. Only add new sections at the bottom of the menu.

**Acceptance**:

- Menu bar shows 🟢 Stable or 🟡 Drift in the network baseline section
- Clicking reveals which fields changed
- "Trust Current" saves a new baseline
- All existing network topology features continue to work

---

### Task 5: Update README install section

**File**: `README.md`

Add a short "Network Baseline Monitor" section to README that explains:

- What it does in one sentence
- How to trust a baseline: `scripts/nbm-trust.sh --yes`
- How to check: `scripts/nbm-check.sh`
- Where the baseline is stored: `~/.network-baseline/baseline.json`

---

## Execution Order

1. Task 1 (data model) — no dependencies
2. Task 2 (trust) — depends on Task 1
3. Task 3 (check) — depends on Task 1
4. Task 4 (SwiftBar) — depends on Tasks 2, 3
5. Task 5 (README) — can be done in parallel with Task 4

---

## What NOT to add in v0.1

- Docker checks
- Browser fingerprint
- Claude Code detection
- MCP server inspection
- API key scanning
- IP reputation or risk scoring
- Account restriction warnings
