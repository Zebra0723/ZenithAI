#!/usr/bin/env bun
// Zenith: joins Galaxy Link as the member `zenith` and takes on missions, one at a
// time, each in its own sandboxed folder, through Claude Code on your Max plan.
//
// Any member can hand Zenith a mission ("Zenith: build the tennis team a website",
// "make this a mission"). When it's done, the result goes back the way Link routes
// everything: to your screen if you're at the Mac, to your phone through Comet if not.

import { GalaxyLink, type LinkTask } from "./client";
import { configFromEnv, missionFolder, missionPrompt } from "./missions";
import { runClaude } from "./runner";

const config = configFromEnv();
const link = new GalaxyLink("zenith", { name: "Zenith", powers: ["missions"], version: "0.1.0" });

export async function handleMission(task: LinkTask): Promise<{ ok: boolean; result: string }> {
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
}

if (import.meta.main) {
  console.log(`zenith: taking missions into ${config.root}, model ${config.model}, up to ${config.maxMinutes} min each`);
  // One mission at a time: the next is only collected once this one finishes.
  link.run({ onTask: handleMission });
  const quit = async () => {
    await link.goodbye();
    process.exit(0);
  };
  process.on("SIGTERM", quit);
  process.on("SIGINT", quit);
}
