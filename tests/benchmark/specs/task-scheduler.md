Implement a `TaskScheduler` in src/scheduler.ts using TypeScript.

- `constructor(concurrency: number)` — max concurrent tasks. Throw if < 1.
- `schedule<T>(fn: () => Promise<T>): Promise<T>` — queue a task, resolve when it completes. If under the concurrency limit, run immediately. Otherwise wait for a slot.
- `get pending(): number` — number of queued tasks waiting to run.
- `get running(): number` — number of currently executing tasks.
- `drain(): Promise<void>` — resolve when all scheduled tasks (queued + running) have completed.

Include tests in src/scheduler.test.ts using vitest. Test concurrent execution limits with real async delays.
