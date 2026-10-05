// @vitest-environment node
import { describe, expect, it } from 'vitest';
import type { Frame, Handle } from '../../src/lib/gridtopinn';
import { createRunner, type RunPlan } from '../../src/lib/experiments/runner.svelte';

type RunOpts = Parameters<Parameters<typeof createRunner>[0]['run']>[0];

/** Fake client: records calls; run() emits one frame synchronously, then resolves via a deferred. */
function fake() {
	let nextHandle = 1;
	const calls: string[] = [];
	const released: number[] = [];
	const pendingRuns: { opts: RunOpts; resolve: () => void }[] = [];
	const rejectNext: { error?: Error } = {};
	let t = 0;
	const client = {
		call: async (fn: string) => {
			calls.push(fn);
			return { handle: nextHandle++ } as Handle;
		},
		release: async (hs: Handle[]) => {
			released.push(...hs.map((h) => h.handle));
		},
		run: (opts: RunOpts) => {
			const emit = () => opts.onFrame?.({ frame: 1, result: 0, vectors: [new Float64Array([1, 0])], scalars: [0.1, (t += 0.1)] } as Frame);
			if (rejectNext.error) {
				const e = rejectNext.error;
				rejectNext.error = undefined;
				return { done: Promise.reject(e), stop: async () => {} };
			}
			const done = new Promise<{ frames: number; stopped: boolean }>((resolve) => {
				pendingRuns.push({ opts, resolve: () => (emit(), resolve({ frames: 1, stopped: false })) });
			});
			return { done, stop: async () => {} };
		}
	};
	return { client, calls, released, pendingRuns, rejectNext };
}

function manualScheduler() {
	const queue: (() => void)[] = [];
	return { schedule: (cb: () => void) => void queue.push(cb), queue, flush: () => queue.splice(0).forEach((cb) => cb()) };
}
const tick = () => new Promise((r) => setTimeout(r, 0));

function plan(over: Partial<RunPlan> = {}): RunPlan {
	return {
		precision: 'f64',
		create: { fn: 'make', args: [] },
		advance: (sim) => ({ fn: 'adv', args: [sim] }),
		vectors: (sim) => [{ fn: 'field', args: [sim] }],
		scalars: (sim) => [{ fn: 'err', args: [sim] }],
		frames: 3,
		diverged: () => false,
		...over
	};
}

/** Drive one tick: run the scheduled callback, then let the fake run resolve its frame. */
async function step(f: ReturnType<typeof fake>, s: ReturnType<typeof manualScheduler>) {
	s.flush();
	await tick();
	f.pendingRuns.shift()?.resolve();
	await tick();
}

function setup(over: Partial<RunPlan> = {}) {
	const f = fake();
	const s = manualScheduler();
	const seen: Frame[] = [];
	const runner = createRunner(f.client, (fr) => seen.push(fr), s.schedule);
	return { f, s, seen, runner, p: plan(over) };
}

describe('paced runner', () => {
	it('runs `frames` ticks then is done', async () => {
		const { f, s, seen, runner, p } = setup();
		await runner.start(p);
		expect(runner.status).toBe('running');
		for (let i = 0; i < 3; i++) await step(f, s);
		expect(runner.status).toBe('done');
		expect(seen.length).toBe(3);
		expect(runner.frame).toBe(3);
		expect(s.queue.length).toBe(0);
	});

	it('pause stops after the in-flight frame; resume continues the same sim', async () => {
		const { f, s, runner, p } = setup();
		await runner.start(p);
		s.flush();
		await tick();
		runner.pause(); // frame 1 is in flight
		expect(runner.status).toBe('paused');
		f.pendingRuns.shift()!.resolve();
		await tick();
		expect(runner.frame).toBe(1);
		expect(s.queue.length).toBe(0); // loop exited
		const firstSim = 1;
		runner.resume();
		expect(runner.status).toBe('running');
		await tick(); // the resumed loop schedules its next tick
		const seenSims = new Set<number>();
		for (let i = 0; i < 2; i++) {
			s.flush();
			await tick();
			seenSims.add((f.pendingRuns[0].opts.args[0] as Handle).handle);
			f.pendingRuns.shift()!.resolve();
			await tick();
		}
		expect([...seenSims]).toEqual([firstSim]);
		expect(runner.status).toBe('done');
		expect(runner.frame).toBe(3);
		expect(f.calls.filter((c) => c === 'make').length).toBe(1);
	});

	it('start() during a run supersedes: old sim released once, late frame dropped, counter restarts', async () => {
		const { f, s, seen, runner, p } = setup({ frames: 5 });
		await runner.start(p);
		s.flush();
		await tick();
		const late = f.pendingRuns.shift()!; // in flight for run 1
		await runner.start(p);
		expect(f.released).toEqual([1]);
		expect(runner.frame).toBe(0);
		late.resolve(); // a frame for the stale run arrives late
		await tick();
		expect(seen.length).toBe(0);
		expect(runner.frame).toBe(0);
		expect(f.released).toEqual([1]);
		await step(f, s);
		expect(runner.frame).toBe(1);
		expect(seen.length).toBe(1);
	});

	it('plan.diverged stops scheduling and sets diverged', async () => {
		const { f, s, runner, p } = setup({ diverged: () => true });
		await runner.start(p);
		await step(f, s);
		expect(runner.status).toBe('diverged');
		expect(s.queue.length).toBe(0);
	});

	it('a rejecting run sets error; a later start() recovers', async () => {
		const { f, s, runner, p } = setup();
		await runner.start(p);
		f.rejectNext.error = new Error('boom');
		s.flush();
		await tick();
		expect(runner.status).toBe('error');
		expect(runner.error).toBe('boom');
		await runner.start(p);
		expect(runner.status).toBe('running');
		expect(runner.error).toBe('');
	});

	it('dispose releases the sim and ignores later frames', async () => {
		const { f, s, seen, runner, p } = setup();
		await runner.start(p);
		s.flush();
		await tick();
		const inflight = f.pendingRuns.shift()!;
		runner.dispose();
		await tick();
		expect(f.released).toEqual([1]);
		inflight.resolve();
		await tick();
		expect(seen.length).toBe(0);
		expect(runner.frame).toBe(0);
	});
});
