<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
	import * as Alert from '$lib/components/ui/alert';
	import { readVector, type Precision, type Step } from '$lib/gridtopinn';
	import AltPicker from '$lib/ui/controls/AltPicker.svelte';
	import ParamControl from '$lib/ui/controls/ParamControl.svelte';
	import PrecisionToggle from '$lib/ui/controls/PrecisionToggle.svelte';
	import CodePanel from '$lib/ui/CodePanel.svelte';
	import ExperimentFrame from '$lib/ui/ExperimentFrame.svelte';
	import LinePlot from '$lib/ui/plot/LinePlot.svelte';
	import type { PlotSeries } from '$lib/ui/plot/types';
	import { formatValue } from '$lib/ui/format';
	import Readout from '$lib/ui/Readout.svelte';
	import Verdict from '$lib/ui/Verdict.svelte';
	import PlaybackControls from '$lib/ui/PlaybackControls.svelte';
	import { EXPERIMENTS, PASS, defaultOf, findParam, initialValues } from './config';
	import { autoPlayback, createPlayback } from './playback.svelte';
	import { revealUpTo } from './reveal';

	let { step }: { step: Step } = $props();

	const m = $derived(step.manifest);
	const cfg = EXPERIMENTS[2];
	const alt = $derived(m.alternatives.find((a) => a.id === cfg.alternative)!);
	const rho = $derived(defaultOf(m, 'ρ'));
	const area = $derived(defaultOf(m, 'A'));
	const froll = $derived(defaultOf(m, 'Froll'));
	const tEnd = $derived(defaultOf(m, 't_end'));
	const kmh = $derived(m.functions.find((f) => f.name === 'trajectory_y')?.display ?? { unit: 'm/s', scale: 1 });

	type Applied = { values: Record<string, number>; method: number; precision: Precision };
	// svelte-ignore state_referenced_locally
	let values = $state(initialValues(step.manifest, cfg));
	// svelte-ignore state_referenced_locally
	let method = $state(step.manifest.alternatives.find((a) => a.id === cfg.alternative)!.options[0].value);
	let precision = $state<Precision>('f64');

	// The selected method is recomputed at most once per animation frame while dragging.
	// The other two curves follow SETTLE_MS after the last change and stay stale in between:
	// at a small Δt each of them is tens of thousands of steps.
	const SETTLE_MS = 150;
	// svelte-ignore state_referenced_locally
	let applied = $state<Applied>({ values: { ...values }, method, precision });
	// svelte-ignore state_referenced_locally
	let settled = $state<Applied>({ values: { ...values }, method, precision });
	let frame = 0;
	let timer: ReturnType<typeof setTimeout> | undefined;
	$effect(() => {
		const next = { values: { ...values }, method, precision };
		cancelAnimationFrame(frame);
		clearTimeout(timer);
		frame = requestAnimationFrame(() => (applied = next));
		timer = setTimeout(() => (settled = next), SETTLE_MS);
	});
	onMount(() => () => {
		cancelAnimationFrame(frame);
		clearTimeout(timer);
	});

	type Run = { t: ArrayLike<number>; v: ArrayLike<number>; tr: unknown };
	function run(optionValue: number, a: Applied): Run {
		const v = a.values;
		const tr = step.fn('drs_run', a.precision)(
			optionValue, v['Δt'], v.rtol, v.P, v.m, rho, area, froll, v.Cd_closed, v.Cd_open, v.t_open, tEnd
		);
		const t = readVector(step, step.fn('trajectory_t', a.precision)(tr), a.precision);
		const y = readVector(step, step.fn('trajectory_y', a.precision)(tr), a.precision);
		return { t, v: y.map((u) => u * kmh.scale), tr };
	}
	const mutedRuns = (sel: number, a: Applied) =>
		alt.options.filter((o) => o.value !== sel).map((o) => ({ o, r: run(o.value, a) }));

	type Result = {
		series: PlotSeries[];
		vEnd: number;
		target: number;
		relDiff: number;
		steps: number;
		dtMin: number;
		dtMax: number;
		settling: number;
		verdict: 'pass' | 'fail' | 'diverged' | 'none';
		verdictText: string;
		ms: number;
	};

	function seriesOf(o: { label: string; key: string }, r: Run, role: 'primary' | 'muted'): PlotSeries {
		return { label: o.label, role, x: r.t, y: r.v, points: role === 'primary' && o.key === 'adaptive' };
	}

	// Selected method: always fresh.
	const outcome = $derived.by((): { ok: true; r: Result } | { ok: false; message: string } => {
		const { values: v, method: sel, precision: p } = applied;
		const t0 = performance.now();
		try {
			const o = alt.options.find((q) => q.value === sel) ?? alt.options[0];
			const r = run(o.value, applied);
			const target: number = step.fn('top_speed', p)(v.P, rho, v.Cd_open, area, froll) * kmh.scale;
			const settling: number = step.fn('settling_time', p)(r.tr, target / kmh.scale, 0.9);
			const vEnd = r.v[r.v.length - 1];
			const relDiff = Math.abs(vEnd - target) / target;
			let dtMin = Infinity;
			let dtMax = -Infinity;
			for (let i = 1; i < r.t.length; i++) {
				const d = r.t[i] - r.t[i - 1];
				if (d < dtMin) dtMin = d;
				if (d > dtMax) dtMax = d;
			}
			let verdict: Result['verdict'];
			let verdictText: string;
			if (!Number.isFinite(vEnd)) [verdict, verdictText] = ['diverged', '발산'];
			else if (relDiff <= PASS.step2.relTol) [verdict, verdictText] = ['pass', '통과'];
			else [verdict, verdictText] = ['fail', '기준 초과'];
			return {
				ok: true,
				r: {
					series: [seriesOf(o, r, 'primary')],
					vEnd, target, relDiff, steps: r.t.length - 1, dtMin, dtMax, settling,
					verdict, verdictText,
					ms: performance.now() - t0
				}
			};
		} catch (e) {
			return { ok: false, message: e instanceof Error ? e.message : String(e) };
		}
	});

	// The other methods, from the settled parameters.
	// Read the selected method through its own derived: `applied` is replaced every frame, `sel` only changes
	// when the selection does, so this does not re-run per frame.
	const sel = $derived(applied.method);
	const muted = $derived.by((): PlotSeries[] | undefined => {
		const a = settled;
		try {
			return mutedRuns(sel, a).map(({ o, r }) => seriesOf(o, r, 'muted'));
		} catch {
			return undefined; // the selected method's own try/catch reports the error
		}
	});

	// Test hook: counts how often the muted series were recomputed.
	let mutedCount = $state(0);
	$effect(() => {
		void muted;
		untrack(() => mutedCount++);
	});

	// Keep the last good result on screen while a later compute fails.
	let shown = $state<Result | undefined>();
	$effect(() => {
		if (outcome.ok) shown = outcome.r;
	});
	const display = $derived(outcome.ok ? outcome.r : shown);
	const selectedOption = $derived(alt.options.find((o) => o.value === method) ?? alt.options[0]);

	// Playback: the full result exists at once; the bright curve is revealed up to the playback time.
	const PLAY_MS = 4000;
	const RESTART_MS = 200;
	const playback = createPlayback(PLAY_MS);
	const tNow = $derived(playback.progress * tEnd);

	// The curves that do not depend on the playback time. Plot order follows the option order so legend
	// entries stay put when the selection changes; the selected method is drawn as ghost + bright curve.
	const fullSeries = $derived.by((): PlotSeries[] => {
		if (!display) return [];
		const sel = display.series[0];
		const byLabel = new Map((muted ?? []).map((s) => [s.label, s]));
		const ordered = alt.options.flatMap((o): PlotSeries[] => {
			if (o.label === sel.label) return [{ ...sel, role: 'ghost', label: `${sel.label} (전체)`, points: false }, sel];
			const s = byLabel.get(o.label);
			return s ? [s] : [];
		});
		const ref: PlotSeries = {
			label: '목표 속도 (열림 최고속도)',
			role: 'reference',
			x: [0, tEnd],
			y: [display.target, display.target],
			dashed: true
		};
		return [...ordered, ref];
	});

	const head = $derived.by(() => {
		const sel = display?.series[0];
		return sel ? revealUpTo(sel.x, sel.y, tNow) : { x: [], y: [], last: -1 };
	});
	const series = $derived(
		fullSeries.map((s): PlotSeries =>
			s.role === 'primary' ? { ...s, x: head.x, y: head.y, head: true } : s
		)
	);
	// The readouts show the last step the integrator really computed, not the interpolated head point.
	const lastSample = $derived(head.last >= 0 ? { t: display!.series[0].x[head.last], v: display!.series[0].y[head.last] } : undefined);
	const playSpeed = $derived(lastSample?.v);

	autoPlayback(playback, () => [{ ...values }, method, precision], RESTART_MS);

	// Muted curves may have diverged by orders of magnitude: fit the axis to the good curves only.
	const yRange = $derived.by(() => {
		let lo = Infinity;
		let hi = -Infinity;
		for (const s of fullSeries) {
			if (s.role === 'muted') continue;
			for (let i = 0; i < s.y.length; i++) {
				const y = s.y[i];
				if (!Number.isFinite(y)) continue;
				if (y < lo) lo = y;
				if (y > hi) hi = y;
			}
		}
		if (!(hi > lo)) return undefined;
		const pad = (hi - lo) * 0.05;
		return { min: lo - pad, max: hi + pad };
	});
	const markers = $derived([{ x: applied.values.t_open, label: 'DRS 열림' }]);
</script>

<ExperimentFrame computeMs={display?.ms} mutedRuns={mutedCount}>
	{#snippet code()}
		<div class="flex flex-wrap items-end gap-x-6 gap-y-4">
			<AltPicker {alt} bind:value={method} />
			<PrecisionToggle bind:value={precision} />
		</div>
		<CodePanel source={selectedOption.source} label={selectedOption.label} optionKey={selectedOption.key} />
	{/snippet}
	{#snippet controls()}
		<div class="grid gap-x-6 gap-y-5 md:grid-cols-2 xl:grid-cols-1 2xl:grid-cols-2">
			{#each cfg.controls as c (c.name)}
				<ParamControl spec={findParam(m, c.name)} control={c} bind:value={values[c.name]} />
			{/each}
		</div>
	{/snippet}
	{#snippet plot()}
		{#if !outcome.ok}
			<Alert.Root variant="destructive" class="mb-3" role="alert" data-testid="compute-error">
				<TriangleAlert />
				<Alert.Description>{outcome.message}</Alert.Description>
			</Alert.Root>
		{/if}
		<div class="mb-2 flex items-start justify-between gap-3">
			<h2 class="text-sm font-medium">시간이 지나며 최고속도에 다가가는 속도 곡선</h2>
			{#if display}<Verdict verdict={display.verdict} text={display.verdictText} />{/if}
		</div>
		<LinePlot {series} xLabel="t [s]" yLabel="v [{kmh.unit}]" {markers} {yRange} />
		<div class="mt-3"><PlaybackControls {playback} /></div>
	{/snippet}
	{#snippet readouts()}
		{#if display}
			<div class="grid grid-cols-2 gap-x-4 gap-y-5 sm:grid-cols-3">
				<Readout key="play-time" label="재생 시각" value={tNow} unit="s" />
				<Readout key="play-speed" label="직전 계산 걸음의 속도" value={playSpeed} unit={kmh.unit} hint={lastSample ? `재생 시각 이전에 적분기가 마지막으로 계산한 걸음(t = ${formatValue(lastSample.t)} s)의 값` : '아직 계산된 걸음 없음'} />
				<Readout key="v-end" label="t_end의 속도" value={display.vEnd} unit={kmh.unit} />
				<Readout key="target" label="목표 속도" value={display.target} unit={kmh.unit} />
				<Readout key="rel-diff" label="목표와의 상대 차이" value={display.relDiff} />
				<Readout key="settling" label="목표의 90% 도달 시간" value={display.settling} unit="s" />
				<Readout key="steps" label="걸음 수" value={display.steps} />
				<Readout key="dt-min" label="최소 Δt" value={display.dtMin} unit="s" />
				<Readout key="dt-max" label="최대 Δt" value={display.dtMax} unit="s" />
			</div>
		{/if}
	{/snippet}
</ExperimentFrame>
