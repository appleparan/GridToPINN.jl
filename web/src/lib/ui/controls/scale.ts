export type ScaleKind = 'linear' | 'log';
export interface SliderWindow {
	min: number;
	max: number;
	kind: ScaleKind;
	integer: boolean;
}

/** Number of discrete slider positions (positions are integers 0..SLIDER_STEPS). */
export const SLIDER_STEPS = 1000;
const LOG_DECADES_RATIO = 1000;

export function pickScale(min: number, max: number): ScaleKind {
	return min > 0 && max / min >= LOG_DECADES_RATIO ? 'log' : 'linear';
}

export function clamp(value: number, w: SliderWindow): number {
	return Math.min(w.max, Math.max(w.min, value));
}

export function toPosition(value: number, w: SliderWindow): number {
	const v = clamp(value, w);
	const t = w.kind === 'log' ? Math.log(v / w.min) / Math.log(w.max / w.min) : (v - w.min) / (w.max - w.min);
	return Math.min(SLIDER_STEPS, Math.max(0, Math.round(t * SLIDER_STEPS)));
}

export function fromPosition(pos: number, w: SliderWindow): number {
	if (pos <= 0) return w.min;
	if (pos >= SLIDER_STEPS) return w.max;
	const t = pos / SLIDER_STEPS;
	const raw = w.kind === 'log' ? w.min * (w.max / w.min) ** t : w.min + (w.max - w.min) * t;
	return clamp(w.integer ? Math.round(raw) : Number(raw.toPrecision(3)), w);
}

/** Parse user text in display units; returns SI value clamped to w, or undefined for empty/non-numeric. */
export function parseInput(text: string, displayScale: number, w: SliderWindow): number | undefined {
	if (text.trim() === '') return undefined;
	const n = Number(text);
	if (!Number.isFinite(n)) return undefined;
	const si = n / displayScale;
	return clamp(w.integer ? Math.round(si) : si, w);
}
