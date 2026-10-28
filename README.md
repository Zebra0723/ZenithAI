# ZenithAI

Zenith is GalaxyAI's fifth member: give it a whole mission and it works on it for hours, then hands back the finished thing. It joins Galaxy Link as `zenith`, so any member can pass it one: text Comet "Zenith: …", tell Orbit "make this a mission", or ask Nova.

This first version follows option B of `ZENITH_PLAN.md` (in NovaAI). It costs nothing beyond your Claude Max plan.
- **Where it runs:** each mission runs on your Mac through Claude Code, logged into your Max plan. An API key in the environment is ignored on purpose.
- **What it can touch:** each mission works in its own folder in `~/Galaxy/Missions`, inside Claude Code's sandbox. It can write only there, can't read the rest of your home folder, and can only reach an allow list of sites (npm, GitHub, Vercel, PyPI…).
- **How it works:** one mission at a time. A mission stops after 3 hours or 300 turns, it never asks questions, and it writes its assumptions down in `SUMMARY.md`.
- **The result:** goes back through Link, to your screen if you're at the Mac, or to your phone through Comet if you're not.
- **Practice:** Zenith also has the `practice` power. Galaxy Trainer sends drills to its inbox; Zenith plans each one as a dry run (Claude Code with every tool denied, one turn, an empty temporary folder, 90 seconds at most) and answers with its plan: first steps, how it would check its work, assumptions, what it would ask you to approve, and what it would hand back. The lessons come back through Link's context. Missions always win: no drill starts while a mission runs, and a drill in progress is dropped unanswered when one starts.

## Install
You need bun, Claude Code logged into your plan (`claude`, then `/login`), and Galaxy Link running.
```bash
./install.sh
```

## Settings (environment variables in the launch agent)
- `ZENITH_MODEL`: `sonnet` by default.
- `ZENITH_MAX_MINUTES`: `180` by default.
- `ZENITH_MAX_TURNS`: `300` by default.
- `ZENITH_DOMAINS`: the sites missions may reach, comma-separated.
- `ZENITH_MISSIONS`: where mission folders go.

Tests: `bun test`.
