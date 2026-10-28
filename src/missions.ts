// What a mission is on disk, what Zenith tells Claude Code, and how it reads the answer.
//
// Each mission gets its own folder under ~/Galaxy/Missions. Claude Code runs there,
// sandboxed: it can write only inside that folder, can't read the rest of your home
// folder, and can reach only the sites on the allow list. That's how Zenith works for
// hours without touching anything else on your Mac.

import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface MissionConfig {
  /** Where mission folders go. */
  root: string;
  /** The `claude` binary. */
  claude: string;
  /** The model that does the work. */
  model: string;
  /** Stop a mission after this long. */
  maxMinutes: number;
  maxTurns: number;
  /** Hosts the mission may reach. */
  allowedDomains: string[];
  /** Folders outside the mission folder that tools legitimately write to (package caches). */
  allowWrite: string[];
}

export const DEFAULT_DOMAINS = [
  // Search and reading the web is done by Claude Code's own tools, outside the sandbox;
  // these are for what the mission's commands fetch.
  "registry.npmjs.org", "*.npmjs.org", "registry.yarnpkg.com",
  "github.com", "*.github.com", "*.githubusercontent.com",
  "vercel.com", "*.vercel.com", "*.vercel.app",
  "pypi.org", "files.pythonhosted.org",
  "bun.sh", "*.bun.sh", "deno.land", "jsr.io",
];

export function configFromEnv(env: Record<string, string | undefined> = process.env): MissionConfig {
  const list = (v: string | undefined) => (v ? v.split(",").map((s) => s.trim()).filter(Boolean) : undefined);
  const home = homedir();
  return {
    root: env.ZENITH_MISSIONS ?? join(home, "Galaxy", "Missions"),
    claude: env.ZENITH_CLAUDE ?? "claude",
    model: env.ZENITH_MODEL ?? "sonnet",
    maxMinutes: Number(env.ZENITH_MAX_MINUTES ?? 180),
    maxTurns: Number(env.ZENITH_MAX_TURNS ?? 300),
    allowedDomains: list(env.ZENITH_DOMAINS) ?? DEFAULT_DOMAINS,
    allowWrite: list(env.ZENITH_ALLOW_WRITE) ?? [join(home, ".npm"), join(home, ".bun", "install", "cache"), join(home, "Library", "Caches")],
  };
}

/** "Build a website for the tennis team!" → "build-a-website-for-the-tennis-team" */
export function slug(title: string): string {
  return (
    title
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[^\w\s-]/g, "")
      .trim()
      .replace(/[\s_-]+/g, "-")
      .slice(0, 48)
      .replace(/-+$/, "") || "mission"
  );
}

/** ~/Galaxy/Missions/2026-10-28 build-a-website-for-the-tennis-team, made if missing. */
export function missionFolder(root: string, title: string, now = new Date()): string {
  const day = now.toISOString().slice(0, 10);
  const folder = join(root, `${day} ${slug(title)}`);
  mkdirSync(folder, { recursive: true });
  return folder;
}

/** The sandbox Claude Code runs in, as a --settings value. */
export function sandboxSettings(config: MissionConfig): string {
  return JSON.stringify({
    sandbox: {
      enabled: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: false,
      failIfUnavailable: true,
      filesystem: { allowWrite: config.allowWrite, denyRead: ["~/"], allowRead: ["."] },
      network: { allowedDomains: config.allowedDomains },
    },
  });
}

export function claudeArgs(config: MissionConfig, prompt: string): string[] {
  return [
    "-p", prompt,
    "--output-format", "stream-json",
    "--verbose",
    "--model", config.model,
    // Edits inside the folder go ahead; anything that would need a person is refused,
    // and Claude is told nobody can approve it, so it works around it instead of waiting.
    "--permission-mode", "acceptEdits",
    "--permission-prompts", "none",
    "--max-turns", String(config.maxTurns),
    "--settings", sandboxSettings(config),
  ];
}

export interface Mission {
  id: string;
  from: string;
  title: string;
  instructions: string;
}

/** Everything Claude Code is told at the start of a mission. */
export function missionPrompt(mission: Mission, folder: string, galaxy: string | null): string {
  return [
    `You are Zenith, the member of the user's GalaxyAI that takes on whole missions and sees them through. ` +
      `${capitalise(mission.from)} handed you this one.`,
    "",
    `Mission: ${mission.title}`,
    "",
    mission.instructions,
    "",
    "How to work:",
    `- Your workspace is ${folder}. Everything you make goes there. You can't change anything outside it, and you don't need to.`,
    "- Nobody is watching and nobody can answer questions. Never stop to ask. When something is unclear, choose the sensible option, note it as an assumption, and keep going.",
    "- Finish the whole mission, not a first step. Check your own work before you call it done: run what you built, open what you wrote, confirm every fact you state.",
    "- If something truly can't be done from here (it needs the user's accounts, money, or a decision only they can make), do everything around it and say exactly what's left for them.",
    "- When you're done, write SUMMARY.md in the workspace: what you made, where it is (files, links), how to use it, and every assumption you made.",
    "- Your final message is what the user reads first: a few sentences, then the links and file names.",
    ...(galaxy ? ["", "What the Galaxy knows (shared with the other members):", galaxy] : []),
  ].join("\n");
}

const capitalise = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export interface StreamState {
  /** The final answer, once the run ends. */
  result: string | null;
  failed: boolean;
  /** The latest thing Claude said along the way, for progress notes. */
  latest: string;
  turns: number;
}

export function newStreamState(): StreamState {
  return { result: null, failed: false, latest: "", turns: 0 };
}

/** Reads one line of Claude Code's stream-json output into the running state. */
export function readStreamLine(state: StreamState, line: string): void {
  let event: any;
  try {
    event = JSON.parse(line);
  } catch {
    return;
  }
  if (event?.type === "assistant") {
    state.turns++;
    const text = (event.message?.content ?? [])
      .filter((c: any) => c?.type === "text" && typeof c.text === "string")
      .map((c: any) => c.text.trim())
      .filter(Boolean)
      .join(" ");
    if (text) state.latest = text;
  } else if (event?.type === "result") {
    state.result = typeof event.result === "string" ? event.result : "";
    state.failed = Boolean(event.is_error) || (typeof event.subtype === "string" && event.subtype !== "success");
  }
}

/** A progress note from what Claude last said: its first sentence, kept short. */
export function progressNote(text: string): string {
  const first = text.replace(/\s+/g, " ").match(/^.{1,200}?[.!?](\s|$)/)?.[0] ?? text.slice(0, 200);
  return first.trim();
}

// Galaxy Trainer practice drills: a dry run of a mission. Claude Code only plans: it gets
// no tools at all, one turn, and an empty folder, and its plan is the answer.

/** Every tool a practice run is denied (Agent is Task's newer name). */
export const PRACTICE_DISALLOWED_TOOLS = [
  "Bash", "Edit", "Write", "MultiEdit", "NotebookEdit", "WebFetch", "WebSearch",
  "Task", "Agent", "Read", "Glob", "Grep", "TodoWrite",
];
export const PRACTICE_TIMEOUT_MS = 90_000;
export const PRACTICE_MAX_CHARS = 1500;

export function practiceArgs(config: MissionConfig, prompt: string): string[] {
  return [
    "-p", prompt,
    "--output-format", "stream-json",
    "--verbose",
    "--model", config.model,
    "--disallowedTools", PRACTICE_DISALLOWED_TOOLS.join(","),
    "--max-turns", "1",
    "--settings", sandboxSettings(config),
  ];
}

/** The mission prompt for a drill, plus the dry-run rules and the shape of the answer. */
export function practicePrompt(drill: { id: string; text: string }, galaxy: string | null): string {
  const title = drill.text.trim().split("\n")[0].slice(0, 80) || "Practice drill";
  const mission = missionPrompt(
    { id: drill.id, from: "the Galaxy trainer", title, instructions: drill.text.trim() },
    "a fresh folder in ~/Galaxy/Missions (made when a real mission starts)",
    galaxy,
  );
  return [
    mission,
    "",
    "PRACTICE DRILL, DRY RUN: this is practice, not a real mission. Do not start the work and do not use any tools (you have none here). " +
      `Reply only with your plan, in plain text, under ${PRACTICE_MAX_CHARS} characters:`,
    "1. First steps: what you would do first, in order.",
    "2. Checking: how you would check your work before calling it done.",
    "3. Assumptions: what you would assume where the request is unclear.",
    "4. Approval: anything you would ask the user to approve first (spending money, their accounts, sending things in their name, anything that can't be undone), or \"nothing\".",
    "5. Hand-back: what you would hand back at the end, and where.",
  ].join("\n");
}

/** Keeps a practice answer within PRACTICE_MAX_CHARS. */
export function capAnswer(text: string, max = PRACTICE_MAX_CHARS): string {
  const t = text.trim();
  return t.length <= max ? t : t.slice(0, max - 1).trimEnd() + "…";
}
