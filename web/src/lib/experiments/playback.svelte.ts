// Wall-clock playback of an already computed result. Display only: it advances a number from 0 to 1;
// the experiment maps that number onto the kernel-computed samples.
export type PlaybackStatus = 'playing' | 'paused' | 'done';

export interface Playback {
	readonly status: PlaybackStatus;
	/** 0..1 */
	readonly progress: number;
	/** From 'paused' continues; from 'done' restarts at 0. */
	play(): void;
	pause(): void;
	/** progress = 0, status 'playing'. */
	restart(): void;
	/** progress = 1, status 'done' (reduced motion). */
	finish(): void;
	/** Change the total duration; the current progress is kept. */
	setDuration(ms: number): void;
	dispose(): void;
}

export function createPlayback(
	durationMs: number,
	now: () => number = () => performance.now(),
	schedule: (cb: () => void) => void = (cb) => requestAnimationFrame(cb)
): Playback {
	let status = $state<PlaybackStatus>('paused');
	let progress = $state(0);
	let duration = Math.max(1, durationMs);
	let base = 0; // progress at `startedAt`
	let startedAt = 0;
	let queued = false; // exactly one scheduled callback at a time
	let disposed = false;

	function tick() {
		queued = false;
		if (disposed || status !== 'playing') return;
		progress = Math.min(1, base + (now() - startedAt) / duration);
		if (progress >= 1) {
			status = 'done';
			return;
		}
		queue();
	}
	function queue() {
		if (queued || disposed) return;
		queued = true;
		schedule(tick);
	}
	function begin(from: number) {
		base = from;
		progress = from;
		startedAt = now();
		status = 'playing';
		queue();
	}

	return {
		get status() {
			return status;
		},
		get progress() {
			return progress;
		},
		play() {
			if (status === 'playing') return;
			begin(status === 'done' ? 0 : progress);
		},
		pause() {
			if (status !== 'playing') return;
			progress = Math.min(1, base + (now() - startedAt) / duration);
			status = 'paused';
		},
		restart() {
			begin(0);
		},
		finish() {
			progress = 1;
			status = 'done';
		},
		setDuration(ms) {
			const next = Math.max(1, ms);
			if (next === duration) return;
			if (status === 'playing') {
				base = Math.min(1, base + (now() - startedAt) / duration);
				startedAt = now();
			}
			duration = next;
		},
		dispose() {
			disposed = true;
		}
	};
}
