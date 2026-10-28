// Runs Claude Code: a whole mission, or a practice drill's dry run.

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  capAnswer,
  claudeArgs,
  type MissionConfig,
  newStreamState,
  PRACTICE_TIMEOUT_MS,
  practiceArgs,
  progressNote,
  readStreamLine,
  type StreamState,
} from "./missions";

export interface RunOutcome {
  ok: boolean;
  result: string;
}

interface ClaudeRun {
  state: StreamState;
  /** Why Zenith stopped it, or "" if it ended on its own. */
  stoppedFor: string;
  code: number | null;
  stderr: string;
  /** Set when the binary couldn't be started at all. */
  startError?: string;
}

/** Spawns `claude` with the plan login only, reads its stream, and stops it on time or on abort. */
function spawnClaude(opts: {
  claude: string;
  args: string[];
  cwd: string;
  timeoutMs: number;
  timeoutReason: string;
  /** How long after SIGINT before SIGKILL. */
  killAfterMs: number;
  signal?: AbortSignal;
  onUpdate?: (state: StreamState, before: string) => void;
}): Promise<ClaudeRun> {
  return new Promise((resolve) => {
    const env = { ...process.env };
    // An API key would win over the Max plan login. Zenith only ever uses the plan.
    delete env.ANTHROPIC_API_KEY;
    delete env.ANTHROPIC_AUTH_TOKEN;

    const child = spawn(opts.claude, opts.args, { cwd: opts.cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    const state = newStreamState();
    let buffer = "";
    let stderr = "";
    let stoppedFor = "";

    const stop = (why: string) => {
      if (stoppedFor) return;
      stoppedFor = why;
      // SIGINT lets Claude Code end its turn cleanly; SIGKILL if it doesn't in time.
      child.kill("SIGINT");
      setTimeout(() => child.kill("SIGKILL"), opts.killAfterMs).unref?.();
    };
    const timer = setTimeout(() => stop(opts.timeoutReason), opts.timeoutMs);
    const onAbort = () => stop("it was stopped");
    if (opts.signal?.aborted) onAbort();
    else opts.signal?.addEventListener("abort", onAbort, { once: true });
    const done = (run: Omit<ClaudeRun, "state">) => {
      clearTimeout(timer);
      opts.signal?.removeEventListener("abort", onAbort);
      resolve({ state, ...run });
    };

    child.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
      let nl: number;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line) continue;
        const before = state.latest;
        readStreamLine(state, line);
        opts.onUpdate?.(state, before);
      }
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr = (stderr + chunk.toString("utf8")).slice(-4000);
    });
    child.on("error", (error) => done({ stoppedFor, code: null, stderr, startError: error.message }));
    child.on("close", (code) => {
      if (buffer.trim()) readStreamLine(state, buffer.trim());
      done({ stoppedFor, code, stderr });
    });
  });
}

export async function runClaude(
  config: MissionConfig,
  folder: string,
  prompt: string,
  onProgress: (note: string) => void,
  signal?: AbortSignal,
): Promise<RunOutcome> {
  let lastNote = 0;
  const { state, stoppedFor, code, stderr, startError } = await spawnClaude({
    claude: config.claude,
    args: claudeArgs(config, prompt),
    cwd: folder,
    timeoutMs: config.maxMinutes * 60_000,
    timeoutReason: `it ran past ${config.maxMinutes} minutes`,
    killAfterMs: 20_000,
    signal,
    onUpdate: (s, before) => {
      if (s.latest !== before && Date.now() - lastNote > 60_000) {
        lastNote = Date.now();
        onProgress(progressNote(s.latest));
      }
    },
  });
  if (startError !== undefined) {
    return { ok: false, result: `Zenith couldn't start Claude Code (${startError}). Is it installed and logged in?` };
  }
  if (stoppedFor) {
    const sofar = state.result ?? state.latest;
    return { ok: false, result: `Zenith stopped because ${stoppedFor}.${sofar ? `\n\nWhere it got to: ${sofar}` : ""}` };
  }
  if (state.result !== null) return { ok: !state.failed, result: state.result || "Done." };
  const why = stderr.trim().split("\n").slice(-3).join(" ") || `Claude Code exited with code ${code}`;
  return { ok: false, result: `The mission didn't finish: ${why}` };
}

/**
 * A practice drill's dry run: Claude Code plans the mission with no tools, one turn, in a
 * fresh empty folder. Resolves to the plan (capped), or null when there's nothing worth
 * sending (it couldn't start, timed out, was stopped, or said nothing).
 */
export async function runPractice(
  config: MissionConfig,
  prompt: string,
  opts: { signal?: AbortSignal; timeoutMs?: number } = {},
): Promise<string | null> {
  const folder = mkdtempSync(join(tmpdir(), "zenith-practice-"));
  try {
    const { state, stoppedFor, startError } = await spawnClaude({
      claude: config.claude,
      args: practiceArgs(config, prompt),
      cwd: folder,
      timeoutMs: opts.timeoutMs ?? PRACTICE_TIMEOUT_MS,
      timeoutReason: "the dry run ran too long",
      killAfterMs: 5_000,
      signal: opts.signal,
    });
    if (startError !== undefined || stoppedFor) return null;
    const plan = (state.result || state.latest).trim();
    return plan ? capAnswer(plan) : null;
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}
