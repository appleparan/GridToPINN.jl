import type { Manifest, ParamSpec } from '../gridtopinn/types';
import { pickScale, type SliderWindow } from '../ui/controls/scale';

export interface ControlSpec {
	name: string;
	/** Slider window narrower than the manifest range. */
	window?: { min: number; max: number };
	integer?: boolean;
	/** Initial value when it should differ from the manifest default. */
	initial?: number;
}
export interface ExperimentConfig {
	step: number;
	/** Id of the manifest alternative shown as the toggle. */
	alternative: string;
	controls: ControlSpec[];
}

export const EXPERIMENTS: Record<number, ExperimentConfig> = {
	1: {
		step: 1,
		alternative: 'derivative',
		controls: [
			{ name: 'P' },
			{ name: 'Cd_closed' },
			{ name: 'Cd_open' },
			{ name: 'Froll' },
			{ name: 'v0', window: { min: 0, max: 300 } },
			{ name: 'h' }
		]
	},
	2: {
		step: 2,
		alternative: 'integrator',
		controls: [
			{ name: 'P' },
			{ name: 'm' },
			{ name: 'Cd_closed' },
			{ name: 'Cd_open' },
			{ name: 't_open', window: { min: 0, max: 60 } },
			{ name: 'Δt' },
			{ name: 'rtol', window: { min: 1e-10, max: 0.1 } }
		]
	},
	3: {
		step: 3,
		alternative: 'integrator',
		controls: [
			{ name: 'N', window: { min: 8, max: 400 }, integer: true },
			{ name: 'L', window: { min: 0.005, max: 1 }, initial: 0.02 },
			{ name: 'ν' },
			{ name: 'U', window: { min: 0.1, max: 10 } },
			{ name: 'Δt', window: { min: 1e-4, max: 10 } }
		]
	}
};

/** Pass criteria shown in the verdict badge. */
export const PASS = {
	/** vs analytic, only when Froll === 0 */
	step1: { relTol: { f64: 1e-8, f32: 1e-4 } },
	/** |v(t_end) - top_speed| / top_speed */
	step2: { relTol: 1e-3 },
	/** max error <= fractionOfU * U */
	step3: { fractionOfU: 0.02 }
} as const;

export function findParam(m: Manifest, name: string): ParamSpec {
	const p = m.parameters.find((q) => q.name === name);
	if (!p) throw new Error(`step ${m.step}: unknown parameter "${name}"`);
	return p;
}

export function windowOf(p: ParamSpec, c: ControlSpec): SliderWindow {
	const { min, max } = c.window ?? p;
	return { min, max, kind: pickScale(min, max), integer: c.integer ?? false };
}

export function initialValues(m: Manifest, cfg: ExperimentConfig): Record<string, number> {
	return Object.fromEntries(cfg.controls.map((c) => [c.name, c.initial ?? findParam(m, c.name).default]));
}

/** Manifest default for an argument that has no slider. */
export function defaultOf(m: Manifest, name: string): number {
	return findParam(m, name).default;
}
