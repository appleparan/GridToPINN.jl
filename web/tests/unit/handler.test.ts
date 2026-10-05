import { describe, expect, it } from 'vitest';
import { handleMessage, loadStep, newState, runFrame, type Handle, type Response } from '../../src/lib/gridtopinn';
import { BASE_URL, fileFetch } from './helpers';

async function ready() {
	const s = newState();
	s.step = await loadStep(BASE_URL, 3, fileFetch);
	return s;
}
const ok = (r: Response) => {
	if (r.type !== 'ok') throw new Error(JSON.stringify(r));
	return r.result;
};

describe('worker handler (pure)', () => {
	it('keeps GC refs in the handle table and reads vectors back', async () => {
		const s = await ready();
		const sim = ok(handleMessage(s, { id: 1, op: 'call', fn: 'moving_wall', precision: 'f64', args: [10, 0.1, 1, 1e-5] })) as Handle;
		expect(typeof sim.handle).toBe('number');
		const u = ok(handleMessage(s, { id: 2, op: 'call', fn: 'field', precision: 'f64', args: [sim] })) as Handle;
		const vec = ok(handleMessage(s, { id: 3, op: 'read', handle: u.handle, precision: 'f64' })) as Float64Array;
		expect(vec.length).toBe(11);
		expect(vec[0]).toBe(1);
		const t = ok(handleMessage(s, { id: 4, op: 'call', fn: 'advance', precision: 'f64', args: [sim, 0.01, 5, 3] }));
		expect(t).toBeCloseTo(0.05, 12);
	});
	it('release removes handles and later use is an error response', async () => {
		const s = await ready();
		const sim = ok(handleMessage(s, { id: 1, op: 'call', fn: 'moving_wall', precision: 'f32', args: [10, 0.1, 1, 1e-5] })) as Handle;
		ok(handleMessage(s, { id: 2, op: 'release', handles: [sim.handle] }));
		const r = handleMessage(s, { id: 3, op: 'call', fn: 'field', precision: 'f32', args: [sim] });
		expect(r).toMatchObject({ id: 3, type: 'error' });
		expect((r as { message: string }).message).toMatch(/핸들/);
	});
	it('errors: unknown function, not loaded', async () => {
		const s = await ready();
		expect(handleMessage(s, { id: 1, op: 'call', fn: 'zzz', precision: 'f64', args: [] })).toMatchObject({ type: 'error' });
		expect(handleMessage(newState(), { id: 2, op: 'call', fn: 'time', precision: 'f64', args: [] })).toMatchObject({ type: 'error', message: expect.stringMatching(/load/) });
	});
	it('run frames carry vectors and scalars, and results do not leak handles', async () => {
		const s = await ready();
		const sim = ok(handleMessage(s, { id: 1, op: 'call', fn: 'moving_wall', precision: 'f64', args: [20, 0.1, 1, 1e-5] })) as Handle;
		const u = ok(handleMessage(s, { id: 2, op: 'call', fn: 'field', precision: 'f64', args: [sim] })) as Handle;
		const msg = {
			id: 9, op: 'run' as const, precision: 'f64' as const, fn: 'advance', args: [sim, 0.01, 10, 2], frames: 3,
			vectors: [u], scalars: [{ fn: 'time', args: [sim] }, { fn: 'moving_wall_error', args: [sim, 1] }]
		};
		const before = s.handles.size;
		const frames = [1, 2, 3].map((k) => runFrame(s, msg, k));
		expect(s.handles.size).toBe(before);
		const times = frames.map((f) => (f.type === 'frame' ? f.scalars[0] : NaN));
		expect(times[0]).toBeCloseTo(0.1, 12);
		expect(times[2]).toBeCloseTo(0.3, 12);
		expect(frames[0].type === 'frame' && frames[0].vectors[0].length).toBe(21);
	});
	it('stop marks the run id as cancelled', async () => {
		const s = await ready();
		ok(handleMessage(s, { id: 5, op: 'stop', target: 9 }));
		expect(s.cancelled.has(9)).toBe(true);
	});
});
