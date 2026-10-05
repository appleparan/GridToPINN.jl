// Paced runner: one Worker `run` of a single frame per animation tick, so the plot is watched
// at display rate, pause is trivial (just stop scheduling), and at most one frame is in flight.
import type { Arg, CallSpec, Client, Frame, Handle, Precision } from '$lib/gridtopinn';

export type RunStatus = 'idle' | 'running' | 'paused' | 'done' | 'diverged' | 'error';

export interface RunPlan {
	precision: Precision;
	/** Returns the simulation handle. */
	create: CallSpec;
	/** One frame of work. */
	advance: (sim: Handle) => CallSpec;
	vectors: (sim: Handle) => CallSpec[];
	scalars: (sim: Handle) => CallSpec[];
	frames: number;
	diverged: (f: Frame) => boolean;
}

export interface Runner {
	readonly status: RunStatus;
	readonly frame: number;
	readonly error: string;
	/** Supersedes any current run: the old sim is released and its late frames are dropped. */
	start(plan: RunPlan): Promise<void>;
	pause(): void;
	resume(): void;
	/** Supersede and release; the caller terminates the Worker. */
	dispose(): void;
}

export function createRunner(
	client: Pick<Client, 'call' | 'run' | 'release'>,
	onFrame: (f: Frame, plan: RunPlan) => void,
	schedule: (cb: () => void) => void = (cb) => requestAnimationFrame(cb)
): Runner {
	let status = $state<RunStatus>('idle');
	let frame = $state(0);
	let error = $state('');

	let token = 0; // bumped by start/dispose: identifies the current run
	let loopId = 0; // bumped by pause/resume/start: identifies the current loop of that run
	let sim: Handle | undefined;
	let plan: RunPlan | undefined;
	let inflight: Promise<unknown> | undefined;

	const message = (e: unknown) => (e instanceof Error ? e.message : String(e));

	function releaseSim() {
		const old = sim;
		sim = undefined;
		if (old) client.release([old]).catch(() => {});
	}

	async function loop(tok: number, lid: number) {
		await inflight?.catch(() => {}); // never two frames in flight, even after pause + resume
		while (tok === token && lid === loopId && status === 'running' && sim && plan) {
			await new Promise<void>((r) => schedule(r));
			if (tok !== token || lid !== loopId || status !== 'running') return;
			const p = plan;
			const s = sim;
			let broke = false;
			const run = client.run({
				...p.advance(s),
				precision: p.precision,
				frames: 1,
				vectors: p.vectors(s),
				scalars: p.scalars(s),
				onFrame: (f) => {
					if (tok !== token) return; // late frame of a superseded run
					frame += 1;
					onFrame(f, p);
					if (p.diverged(f)) broke = true;
				}
			});
			inflight = run.done;
			try {
				await run.done;
			} catch (e) {
				if (tok === token) {
					error = message(e);
					status = 'error';
				}
				return;
			}
			if (tok !== token) return;
			if (broke) {
				status = 'diverged';
				return;
			}
			if (frame >= p.frames) {
				status = 'done';
				return;
			}
		}
	}

	return {
		get status() {
			return status;
		},
		get frame() {
			return frame;
		},
		get error() {
			return error;
		},
		async start(next) {
			const tok = ++token;
			loopId++;
			releaseSim();
			plan = next;
			frame = 0;
			error = '';
			try {
				const handle = (await client.call(next.create.fn, next.precision, next.create.args as Arg[])) as Handle;
				if (tok !== token) {
					client.release([handle]).catch(() => {}); // superseded while creating
					return;
				}
				sim = handle;
			} catch (e) {
				if (tok === token) {
					error = message(e);
					status = 'error';
				}
				return;
			}
			status = 'running';
			void loop(tok, loopId);
		},
		pause() {
			if (status !== 'running') return;
			loopId++;
			status = 'paused';
		},
		resume() {
			if (status !== 'paused') return;
			loopId++;
			status = 'running';
			void loop(token, loopId);
		},
		dispose() {
			token++;
			loopId++;
			releaseSim();
			plan = undefined;
			frame = 0;
			status = 'idle';
		}
	};
}
