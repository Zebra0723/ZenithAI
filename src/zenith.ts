#!/usr/bin/env bun
// Zenith: joins Galaxy Link as the member `zenith` and takes on missions, one at a
// time, each in its own sandboxed folder, through Claude Code on your Max plan.
//
// Any member can hand Zenith a mission ("Zenith: build the tennis team a website",
// "make this a mission"). When it's done, the result goes back the way Link routes
// everything: to your screen if you're at the Mac, to your phone through Comet if not.
//
// Between missions it also takes Galaxy Trainer practice drills: it plans each one as a
// dry run (no tools) and sends the plan back to be graded.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { GalaxyLink, type LinkTask } from "./client";
import { configFromEnv, missionFolder, missionPrompt } from "./missions";
import { Practice } from "./practice";
import { runClaude } from "./runner";

export const POWERS = ["missions", "practice"];

// Signed in the way Comet is: the year-long Claude token `galaxy login` saves, so Claude Code
// works from launchd without Terminal's login. Never an API key (runner.ts removes one).
if (!process.env.CLAUDE_CODE_OAUTH_TOKEN) {
  try {
    const saved = readFileSync(join(homedir(), "Library", "Application Support", "Galaxy", "claude-token"), "utf8").trim();
    if (saved) process.env.CLAUDE_CODE_OAUTH_TOKEN = saved;
  } catch {}
}

const config = configFromEnv();
const link = new GalaxyLink("zenith", { name: "Zenith", powers: POWERS, version: "0.1.0" });
const practice = new Practice(link, config);

export async function handleMission(task: LinkTask): Promise<{ ok: boolean; result: string }> {
  practice.missionStarted();
  try {
    const folder = missionFolder(config.root, task.title);
    await link.progress(task.id, "Mission started.");
    const galaxy = await link.context(1500);
    const outcome = await runClaude(
      config,
      folder,
      missionPrompt(task, folder, galaxy),
      (note) => void link.progress(task.id, note),
    );
    await link.note(`${outcome.ok ? "finished the mission" : "stopped the mission"}: ${task.title}`, folder);
    return { ok: outcome.ok, result: `${outcome.result}\n\nEverything is in ${folder}` };
  } finally {
    practice.missionEnded();
  }
}

if (import.meta.main) {
  console.log(`zenith: taking missions into ${config.root}, model ${config.model}, up to ${config.maxMinutes} min each`);
  // One mission at a time: the next is only collected once this one finishes.
  // Practice drills come through the inbox, one at a time, only while no mission runs.
  link.run({
    onTask: handleMission,
    onInbox: async (item) => {
      if (item.kind === "practice") await practice.handle(item);
    },
  });
  const quit = async () => {
    await link.goodbye();
    process.exit(0);
  };
  process.on("SIGTERM", quit);
  process.on("SIGINT", quit);
}
