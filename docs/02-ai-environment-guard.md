# AI Environment Guard

AI Environment Guard（AEG，AI 运行环境哨兵）在 Network Baseline Monitor
之上增加 AI 软件运行感知、状态升级、事件记录和后续告警能力。

它不预测账号是否会被封禁，也不尝试绕过平台限制。它只报告能够观测的环境事实：
当前环境是否符合用户确认的可信配置，以及关键变化发生时是否有受监测的 AI 软件正在运行。

## Product Goal

建立以下闭环：

1. 启动 AI 软件前检查环境是否符合可信配置。
2. AI 软件运行期间持续监测关键环境变化。
3. 发生变化时给出明确级别、事实原因和处理建议。
4. 只在状态变化时记录事件，形成可审计历史。

## Architecture

~~~mermaid
flowchart LR
    NBM["Network Baseline Monitor<br/>IP / Country / ASN / DNS / IPv6"]
    PROC["AI Process Detector<br/>Claude / Codex / ChatGPT / Gemini"]
    ASSESS["AEG Assessment Engine<br/>ready / caution / alert / unknown"]
    HISTORY["Change-only History<br/>~/.nbm/history.jsonl"]
    UI["SwiftBar / macOS Notification / Preflight"]

    NBM --> ASSESS
    PROC --> ASSESS
    ASSESS --> HISTORY
    ASSESS --> UI
~~~

### Modules

- config/ai-apps.tsv: monitored app definitions and process include/exclude rules.
- scripts/aeg-processes.sh: read-only AI process detection.
- scripts/aeg-assess.sh: combines network state with running applications.
- scripts/aeg-history.sh: writes JSONL only when the assessment fingerprint changes.
- scripts/aeg-common.sh: shared paths and JSON escaping.

NBM remains the owner of network collection and baseline comparison. AEG consumes its result;
it does not introduce a second network detection implementation.

## Status Model

| Status | Severity | Condition | Expected action |
| --- | ---: | --- | --- |
| ready | 0 | Network stable | Continue and monitor |
| caution | 2 | Network drift, no monitored AI running | Restore trusted environment before launch |
| alert | 3 | Drift or visibility loss while AI is running | Pause requests, restore environment, recheck |
| unknown | 2 | Baseline or process detection unavailable | Repair detection before launch |

These are operational readiness states, not account-risk probabilities.

## Assessment Contract

An assessment is a single-line JSON object:

~~~json
{
  "version": 1,
  "checked_at": "2026-07-10T03:00:00Z",
  "status": "alert",
  "severity": 3,
  "network": {
    "status": "drift",
    "changes": [
      {
        "field": "public_ipv4",
        "old": "203.0.113.10",
        "new": "198.51.100.77"
      }
    ]
  },
  "running_apps": [
    {
      "id": "codex-cli",
      "label": "Codex CLI",
      "pids": [1234]
    }
  ],
  "reasons": [
    {
      "code": "network_drift_while_ai_running",
      "message": "AI 软件运行期间检测到网络环境漂移。"
    }
  ],
  "actions": [
    {
      "code": "pause_ai_and_restore_network",
      "message": "暂停 AI 请求，检查 VPN 或代理，恢复可信网络后重新检测。"
    }
  ]
}
~~~

## Event History

aeg-assess.sh --record writes to ~/.nbm/history.jsonl.

- The first assessment is recorded.
- Identical state is not recorded again.
- Network changes, application changes, or severity changes create a new event.
- AEG_HISTORY_MAX_ENTRIES defaults to 500; older lines are removed.
- History contains environment facts and process identifiers, not prompts, API keys, cookies,
  account credentials, or browser content.

## Current Scope

The initial profiles cover:

- ChatGPT desktop
- Codex desktop
- Codex CLI
- Claude Code
- Gemini CLI

Profiles are configuration, not hard-coded policy. More applications can be added without changing
the assessment engine.

## Delivery Phases

### Phase 1: Framework

- Process profiles and detection
- Assessment state machine
- Change-only JSONL history
- Installer and tests

### Phase 2: SwiftBar Alert Surface

- Show AEG readiness above network details
- Show running AI applications
- Record assessments on refresh
- Send a macOS notification only on transitions into alert

### Phase 3: Preflight

- One-command readiness check before starting a CLI
- Per-application trusted profiles
- Clear recovery checklist

### Phase 4: System and Browser Consistency

- Timezone, locale, language, endpoint and proxy consistency
- Browser-visible checks remain a separate module
- Weak correlation signals are displayed as facts, not converted into a ban-risk score

## Safety Boundaries

- No claim that a green state prevents account restrictions.
- No automatic account login, proxy switching, fingerprint masking, or platform-control bypass.
- No automatic process termination in the first release.
- High-severity actions require explicit user confirmation.
