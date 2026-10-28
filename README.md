# Zenith

**Zenith is the commander of the Galaxy.** Give it a big goal and it runs the whole Galaxy to get it done over hours, days or weeks. It works on a computer of its own and brings in Nova (the Mac), Comet (phone and iMessage) and Nebula (thumbs up or down) when a mission needs them. The finished result lands on a mission board.

The senses: Comet is text, Orbit is voice, Nova is sight, Nebula is touch, and Zenith is time. It follows `ZENITH_PLAN.md` in NovaAI.

| | Lives in | Does |
|---|---|---|
| **Zenith** | The menu bar, a Mac app, and its own computer | Plans, works, commands the Galaxy, checks its own work |

## How a mission flows

1. **Brief.** In the Zenith app, by texting Comet "Zenith: …", or by asking Orbit or Nova. "Make it a mission" from any conversation sends the conversation along as context.
2. **Forecast.** Opus writes the plan: the steps, which member does each, the model for each, the time, the share of the week it should use, what will need you, and its assumptions. **One thumbs up** launches it, in the app or with Nebula.
3. **No questions at the start.** Zenith decides what it can and writes the assumptions down.
4. **Work.** The cloud computer researches, codes, builds, deploys and makes files. Nova acts on the Mac (pausing the instant you touch the mouse or keyboard). Comet texts you and the people on your allowlist; anyone else needs a thumbs up. Nothing is bought and nothing is posted publicly without one.
5. **Needs you.** It finishes everything that doesn't need you, then waits with **all its questions in one batch**. Yes-or-no questions also go to Nebula's approval mode.
6. **Self-check.** An Opus reviewer checks the work against the brief: it loads the site, runs the code, follows the sources. One fix round if it finds problems.
7. **Done.** Results, a summary and the assumptions go on the board, plus **one Comet text**. Nothing else is ever sent unprompted.
8. **Status on request.** Ask Orbit, Comet or Nova "how's my mission?". Zenith answers from the board, for no tokens.

Several missions can run at once, within what the budget governor allows.

## The app

Click the mark in the menu bar (a horizon with the sun above it; the sun fills in while a mission is working) → **Open Zenith**.

- **Mission board**: Forecast → Working → Needs you → Done → Living.
- **New mission**: the goal goes in, the forecast comes out, one thumbs up launches it.
- **Mission view**: the live timeline, the member working right now, the Galaxy strip, the plan, cloud screen snapshots, usage so far against the forecast, results, the self-check, and **pause, redirect and stop**.
- **Needs you**: every waiting question from every mission, answered in one place.
- **Replay**: a scrubbable time-lapse of each mission, with lanes for Zenith, the cloud computer, Nova, Comet and Nebula.
- **Living**: finished results kept working and up to date on a cadence, silently.
- **Galaxy budget**: this week's usage against the cap, what used it, calibration, and what's waiting for room.
- **Settings**: where missions run, the allowlist, the cap, the overnight window, and permissions.

The look is its own: porcelain pages under a midnight sidebar, one amber "sun" for whatever is live, SF Pro Expanded headlines, SF Mono for every number. No emojis.

## Cost: nothing beyond the Max plan

All of Zenith's AI work runs through **Claude Code logged into your Max plan**, never the paid API. Zenith removes `ANTHROPIC_API_KEY` and the other API variables from the environment of every run, so Claude Code always uses the subscription.

- **Routing**: Opus writes forecasts and reviews; Sonnet does the bulk; Haiku takes tiny steps (Nova and Comet handoffs). The forecast picks a model per step.
- **Few tokens**: the brief and the log live in the workspace (`.zenith/BRIEF.md`, `.zenith/LOG.md`) instead of being repeated in prompts; answers to questions resume the step's own Claude Code session instead of starting over; status answers cost nothing.

### The cloud computer

- **A. Claude Code cloud sessions**: part of the plan, and they keep running with the Mac off. Zenith uses them only after **Settings → Run the check** passes: it starts a tiny cloud session from this Mac and reads its answer back. Cloud missions deliver by deploying or pushing to a repository.
- **B. A sandbox on this Mac** (the default, and the fallback): Claude Code under a `sandbox-exec` profile that can write only to the mission's workspace, Claude Code's own files and caches, and can't read Mail, Messages, Documents, Desktop or Pictures. Nova does what needs the Mac.

### The budget governor

- The whole Galaxy stays under **50% of the weekly Max limit** (adjustable).
- Zenith measures Claude Code's usage on this Mac from its own transcripts (`~/.claude/projects`), adds its cloud runs, and adds estimates for members it can't measure (Comet on its server, Nova on its own key, Orbit). Usage is weighed by model and token kind; **calibrate** it once a week by typing the percentage Claude's usage page shows.
- Missions start only when there's room. Heavy missions wait for the **overnight window**. When usage is tight, parallel missions queue behind the running one. Running missions **pause before the cap** and say why on the board.

> **Known issue (from the plan):** Nova still uses a paid API key. It counts as "estimated" here until it moves onto the Max plan.

## Galaxy Link

Zenith joins Link as body `zenith` with the powers `missions` and `mission_status`, and greets Galaxy Chat with its intro on first connect. The app is the Zenith connector: every call goes outward from the Mac to Link on loopback, so nothing on the Mac is exposed to the internet.

| What | How |
|---|---|
| A new mission from another body | A handoff with `power: "missions"`. The instructions are the brief; a `Context:` section, if present, is the conversation it came from. The handoff is finished with the done text when the mission is done (Link delivers it to wherever you are). |
| "How's my mission?" | A handoff with `power: "mission_status"`, or any handoff that asks it in words. Answered at once from the board. |
| Work for Nova and Comet | Handoffs to `nova` (`screen`) and `comet` (`imessage`), followed until they finish. |
| Launches and yes-or-no questions | Link approvals (`/v1/approvals`), which arm Nebula's camera. Needs NebulaAI's `galaxy-patch`; without it, everything is answered in the app. |
| The done text | A handoff to Comet: "Text the user exactly this". |

## Self-upgrading Galaxy

When a mission needs an ability no member has, the cloud computer builds and tests it as a Claude Code skill (`skills/<name>/SKILL.md`) and reports it. After your thumbs up, Zenith installs it for good: into `~/.claude/skills` for itself, or handed to Comet or Nova through Link to install.

## Setup

Requirements: macOS 14 or later, Xcode or the Swift toolchain (5.10+), and [Claude Code](https://code.claude.com) logged into your Max plan (`claude` then `/login`).

```bash
git clone https://github.com/Zebra0723/ZenithAI.git
```

```bash
cd ZenithAI && scripts/build-app.sh --install
```

Then:

1. Start Galaxy Link (NovaAI's `galaxy/`) if it isn't running, so Zenith can reach Nova, Comet and Nebula.
2. Open Zenith from the menu bar, add the people Comet may text to **Settings → No-approval allowlist**, and calibrate the meter on **Galaxy budget**.
3. Optional: turn on **Launch at login**, and run the cloud check if you want missions on Claude Code cloud sessions.

Everything is stored on your Mac in `~/Library/Application Support/Zenith`: each mission's record, its workspace and its snapshots.

## Project layout

```
Sources/ZenithCore/         Pure Swift, builds and tests on Linux too
  Model.swift               Missions, steps, questions, timeline, living plans
  Usage.swift               Tokens and usage units, by model
  Budget.swift              The budget governor: the week, the cap, overnight, queueing, pausing
  StreamJSON.swift          Claude Code's stream-json, and usage from its transcripts
  Reports.swift             Forecasts, step reports and reviews, parsed from replies
  Prompts.swift             Everything Zenith says to Claude, and the words it says for free
  MissionLogic.swift        Board columns, progress, the allowlist
Sources/Zenith/
  App/                      The app: board, new mission, mission view, needs you, replay,
                            living, budget, settings, theme, menu bar
  Engine/Commander.swift    Runs missions from brief to done, and living missions
  Engine/ClaudeCode.swift   Claude Code headless on the Max plan, sandboxed
  Engine/UsageMeter.swift   Usage from Claude Code's transcripts
  Engine/Store.swift        Missions, settings and usage on disk
  Galaxy/                   Galaxy Link client and the connector loop
Tests/ZenithCoreTests/      Forecast and report parsing, stream parsing, the governor, missions
scripts/build-app.sh        Tests, builds and signs Zenith.app
```

```bash
swift test
```
