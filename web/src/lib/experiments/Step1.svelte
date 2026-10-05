<script lang="ts">
	import { onMount } from 'svelte';
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
	import Readout from '$lib/ui/Readout.svelte';
	import Verdict from '$lib/ui/Verdict.svelte';
	import { EXPERIMENTS, PASS, defaultOf, findParam, initialValues } from './config';

	let { step }: { step: Step } = $props();

	const m = $derived(step.manifest);
	const cfg = EXPERIMENTS[1];
	const alt = $derived(m.alternatives.find((a) => a.id === cfg.alternative)!);
	const rho = $derived(defaultOf(m, 'ρ'));
	const area = $derived(defaultOf(m, 'A'));
	const kmh = $derived(m.functions.find((f) => f.name === 'top_speed_iterates')?.display ?? { unit: 'm/s', scale: 1 });

	// svelte-ignore state_referenced_locally
	let values = $state(initialValues(step.manifest, cfg));
	// svelte-ignore state_referenced_locally
	let method = $state(step.manifest.alternatives.find((a) => a.id === cfg.alternative)!.options[0].value);
	let precision = $state<Precision>('f64');

	// Recompute at most once per animation frame: dragging a slider fires many input events.
	let applied = $state<{ values: Record<string, number>; method: number; precision: Precision }>({
		// svelte-ignore state_referenced_locally
		values: { ...values },
		// svelte-ignore state_referenced_locally
		method,
		// svelte-ignore state_referenced_locally
		precision
	});
	let frame = 0;
	$effect(() => {
		const next = { values: { ...values }, method, precision };
		cancelAnimationFrame(frame);
		frame = requestAnimationFrame(() => (applied = next));
	});
	onMount(() => () => cancelAnimationFrame(frame));

	type Result = {
		series: PlotSeries[];
		vClosed: number;
		vOpen: number;
		gain: number;
		iterations: number;
		relError: number;
		refLabel: string;
		verdict: 'pass' | 'fail' | 'diverged' | 'none';
		verdictText: string;
		ms: number;
	};

	const outcome = $derived.by((): { ok: true; r: Result } | { ok: false; message: string } => {
		const { values: v, method: sel, precision: p } = applied;
		const t0 = performance.now();
		try {
			const iterates = step.fn('top_speed_iterates', p);
			const its = Object.fromEntries(
				alt.options.map((o) => [
					o.key,
					readVector(step, iterates(v.P, rho, v.Cd_closed, area, v.Froll, v.v0, o.value, v.h), p)
				])
			);
			const analytic = v.Froll === 0;
			const ref: number = analytic
				? step.fn('top_speed_analytic', p)(v.P, rho, v.Cd_closed, area)
				: step.fn('top_speed', p)(v.P, rho, v.Cd_closed, area, v.Froll);
			const selected = alt.options.find((o) => o.value === sel) ?? alt.options[0];
			const last = its[selected.key];
			const vClosed = last[last.length - 1];
			const vOpen: number = step.fn('top_speed', p)(v.P, rho, v.Cd_open, area, v.Froll);
			const gain: number = step.fn('drs_gain', p)(v.P, rho, area, v.Froll, v.Cd_closed, v.Cd_open);
			const relError = Math.abs(vClosed - ref) / ref;

			const series: PlotSeries[] = alt.options.map((o) => {
				const it = its[o.key];
				return {
					label: o.label,
					role: o.key === selected.key ? 'primary' : 'muted',
					x: Array.from(it, (_, i) => i),
					y: Array.from(it, (u) => Math.abs(u - ref) * kmh.scale),
					points: true
				};
			});

			let verdict: Result['verdict'];
			let verdictText: string;
			if (!Number.isFinite(vClosed) || !Number.isFinite(relError)) {
				[verdict, verdictText] = ['diverged', '발산'];
			} else if (!analytic) {
				[verdict, verdictText] = ['none', '해석해 없음'];
			} else if (relError <= PASS.step1.relTol[p]) {
				[verdict, verdictText] = ['pass', '통과'];
			} else {
				[verdict, verdictText] = ['fail', '기준 초과'];
			}
			return {
				ok: true,
				r: {
					series,
					vClosed,
					vOpen,
					gain,
					iterations: last.length,
					relError,
					refLabel: analytic ? '해석해' : "손 유도 Newton 수렴값 (Froll ≠ 0이라 해석해 없음)",
					verdict,
					verdictText,
					ms: performance.now() - t0
				}
			};
		} catch (e) {
			return { ok: false, message: e instanceof Error ? e.message : String(e) };
		}
	});

	// Keep the last good result on screen while a later compute fails.
	let shown = $state<Result | undefined>();
	$effect(() => {
		if (outcome.ok) shown = outcome.r;
	});
	const display = $derived(outcome.ok ? outcome.r : shown);
	const selectedOption = $derived(alt.options.find((o) => o.value === method) ?? alt.options[0]);
</script>

<ExperimentFrame computeMs={display?.ms}>
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
			<h2 class="text-sm font-medium">Newton 반복마다 줄어드는 오차</h2>
			{#if display}<Verdict verdict={display.verdict} text={display.verdictText} />{/if}
		</div>
		<LinePlot series={display?.series ?? []} xLabel="반복 횟수" yLabel="|v − v*| [{kmh.unit}]" logY />
		{#if display}
			<p class="text-muted-foreground mt-2 text-xs">기준값: {display.refLabel}</p>
		{/if}
	{/snippet}
	{#snippet readouts()}
		{#if display}
			<div class="grid grid-cols-2 gap-x-4 gap-y-5 sm:grid-cols-3 xl:grid-cols-3">
				<Readout key="v-closed" label="DRS 닫힘 최고속도" value={display.vClosed * kmh.scale} unit={kmh.unit} />
				<Readout key="v-open" label="DRS 열림 최고속도" value={display.vOpen * kmh.scale} unit={kmh.unit} />
				<Readout key="gain" label="DRS 이득" value={display.gain * kmh.scale} unit={kmh.unit} />
				<Readout key="iterations" label="반복 횟수" value={display.iterations} />
				<Readout key="rel-error" label="기준값과의 상대 오차" value={display.relError} />
			</div>
		{/if}
	{/snippet}
</ExperimentFrame>
