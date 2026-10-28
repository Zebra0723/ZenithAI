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
