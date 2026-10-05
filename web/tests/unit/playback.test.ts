// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { createPlayback } from '../../src/lib/experiments/playback.svelte';

function setup(duration = 1000) {
	let t = 0;
	const queue: (() => void)[] = [];
	let maxQueued = 0;
	const pb = createPlayback(
		duration,
		() => t,
		(cb) => {
			queue.push(cb);
			maxQueued = Math.max(maxQueued, queue.length);
		}
	);
	return {
		pb,
		queue,
		advance(ms: number) {
			t += ms;
		},
		tick() {
			queue.splice(0).forEach((cb) => cb());
		},
		maxQueued: () => maxQueued
	};
}

describe('playback', () => {
	it('starts paused-at-zero and plays until progress 1, then done', () => {
		const s = setup();
		s.pb.restart();
		expect(s.pb.status).toBe('playing');
		s.advance(250);
		s.tick();
		expect(s.pb.progress).toBeCloseTo(0.25);
		s.advance(2000);
		s.tick();
		expect(s.pb.progress).toBe(1);
		expect(s.pb.status).toBe('done');
		expect(s.queue.length).toBe(0);
	});

	it('pause freezes progress while time advances; play continues from there', () => {
		const s = setup();
		s.pb.restart();
		s.advance(400);
		s.tick();
		s.pb.pause();
		expect(s.pb.status).toBe('paused');
		s.advance(5000);
		s.tick();
		expect(s.pb.progress).toBeCloseTo(0.4);
		s.pb.play();
		expect(s.pb.status).toBe('playing');
		s.advance(100);
		s.tick();
		expect(s.pb.progress).toBeCloseTo(0.5);
	});

	it('restart() mid-way returns to 0 and plays', () => {
		const s = setup();
		s.pb.restart();
		s.advance(600);
		s.tick();
		s.pb.restart();
		expect(s.pb.progress).toBe(0);
		expect(s.pb.status).toBe('playing');
		s.advance(100);
		s.tick();
		expect(s.pb.progress).toBeCloseTo(0.1);
	});

	it('play() from done restarts at 0', () => {
		const s = setup();
		s.pb.restart();
		s.advance(1500);
		s.tick();
		expect(s.pb.status).toBe('done');
		s.pb.play();
		expect(s.pb.progress).toBe(0);
		expect(s.pb.status).toBe('playing');
	});

	it('finish() jumps to done', () => {
		const s = setup();
		s.pb.restart();
		s.pb.finish();
		expect(s.pb.progress).toBe(1);
		expect(s.pb.status).toBe('done');
		s.tick();
		expect(s.pb.status).toBe('done');
	});

	it('dispose() stops scheduling', () => {
		const s = setup();
		s.pb.restart();
		s.pb.dispose();
		s.advance(100);
		s.tick();
		expect(s.queue.length).toBe(0);
		s.pb.play();
		expect(s.queue.length).toBe(0);
	});

	it('never queues more than one callback, even through pause/play/restart', () => {
		const s = setup();
		s.pb.restart();
		s.pb.pause();
		s.pb.play();
		s.pb.restart();
		s.pb.pause();
		s.pb.play();
		expect(s.queue.length).toBe(1);
		s.advance(10);
		s.tick();
		s.advance(10);
		s.tick();
		expect(s.maxQueued()).toBe(1);
	});

	it('setDuration keeps the current progress and rescales the remaining time', () => {
		const s = setup(1000);
		s.pb.restart();
		s.advance(500);
		s.tick();
		s.pb.setDuration(2000);
		expect(s.pb.progress).toBeCloseTo(0.5);
		s.advance(500);
		s.tick();
		expect(s.pb.progress).toBeCloseTo(0.75);
	});
});
