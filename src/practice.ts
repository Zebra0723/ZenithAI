// Galaxy Trainer practice drills. The trainer sends a drill to Zenith's inbox; Zenith plans
// it as a dry run (no tools, one turn) and answers with the plan. Missions always come
// first: no drill starts while a mission runs, and a drill in flight is dropped (left
// unanswered) the moment a mission starts. One drill at a time.

import type { LinkInboxItem } from "./client";
import { type MissionConfig, practicePrompt } from "./missions";
import { runPractice } from "./runner";

export interface PracticeLink {
  context(timeoutMs?: number): Promise<string | null>;
  practiceAnswer(id: string, answer: string): Promise<unknown>;
}

export class Practice {
  private missions = 0;
  private current: AbortController | null = null;

  constructor(
    private link: PracticeLink,
    private config: MissionConfig,
    private run: typeof runPractice = runPractice,
  ) {}

  /** Call when a mission starts: stops any drill in flight. */
  missionStarted() {
    this.missions++;
    this.current?.abort();
  }

  missionEnded() {
    this.missions = Math.max(0, this.missions - 1);
  }

  /** Handles one inbox item. True if a practice answer was sent. */
  async handle(item: LinkInboxItem): Promise<boolean> {
    if (item.kind !== "practice" || !item.taskId) return false;
    if (this.missions > 0 || this.current) return false;
    const ctl = new AbortController();
    this.current = ctl;
    try {
      const galaxy = await this.link.context(1500);
      if (ctl.signal.aborted) return false;
      const answer = await this.run(this.config, practicePrompt({ id: item.taskId, text: item.text }, galaxy), { signal: ctl.signal });
      if (!answer || ctl.signal.aborted) return false;
      await this.link.practiceAnswer(item.taskId, answer);
      return true;
    } finally {
      this.current = null;
    }
  }
}
