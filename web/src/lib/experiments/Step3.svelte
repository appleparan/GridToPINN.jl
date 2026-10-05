<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
	import * as Alert from '$lib/components/ui/alert';
	import { createClient, type Frame, type Handle, type Precision, type Step } from '$lib/gridtopinn';
	import AltPicker from '$lib/ui/controls/AltPicker.svelte';
	import ParamControl from '$lib/ui/controls/ParamControl.svelte';
	import PrecisionToggle from '$lib/ui/controls/PrecisionToggle.svelte';
	import CodePanel from '$lib/ui/CodePanel.svelte';
	import ExperimentFrame from '$lib/ui/ExperimentFrame.svelte';
	import LinePlot from '$lib/ui/plot/LinePlot.svelte';
	import type { PlotSeries } from '$lib/ui/plot/types';
	import Readout from '$lib/ui/Readout.svelte';
	import RunControls from '$lib/ui/RunControls.svelte';
	import Verdict from '$lib/ui/Verdict.svelte';
	import { EXPERIMENTS, PASS, findParam, initialValues } from './config';
	import { createRunner, type RunPlan } from './runner.svelte';

	let { step }: { step: Step } = $props();

	const FRAMES = 300;
	const STEPS_PER_FRAME = 10;
	const RESTART_MS = 200;
	const Y_MARGIN = 0.04; // fraction of U kept free above and below the profile

	const m = $derived(step.manifest);
	const cfg = EXPERIMENTS[3];
	const alt = $derived(m.alternatives.find((a) => a.id === cfg.alternative)!);

	// svelte-ignore state_referenced_locally
	let values = $state(initialValues(step.manifest, cfg));
	// svelte-ignore state_referenced_locally
	let method = $state(step.manifest.alternatives.find((a) => a.id === cfg.alternative)!.options[0].value);
	let precision = $state<Precision>('f64');

	type Ctx = { N: number; L: number; U: number; nu: number; dt: number; precision: Precision };
	type Plan3 = RunPlan & { ctx: Ctx };
	type Shown = { y: Float64Array; u: ArrayLike<number>; exact: Float64Array; t: number; err: number; depth: number; ctx: Ctx };

	let shown = $state.raw<Shown | undefined>();
	let message = $state('');
	let ready = $state(false);

	// A frame that lands after pause() is not drawn, so a paused picture and its readouts stay frozen.
	// It is kept and drawn when the run leaves 'paused' (resume, or it was the final / diverged frame).
	let late: { f: Frame; plan: RunPlan } | undefined;
	function onFrame(f: Frame, plan: RunPlan) {
		if (runner.status === 'paused' && runner.frame < (plan as Plan3).frames) {
			late = { f, plan };
			return;
		}
		late = undefined;
		draw(f, plan);
	}
	$effect(() => {
		if (runner.status === 'paused' || !late) return;
		const { f, plan } = late;
		late = undefined;
		draw(f, plan);
	});

	function draw(f: Frame, plan: RunPlan) {
		const { N, L, U, nu, precision: p } = (plan as Plan3).ctx;
		const t = f.scalars[1];
		const y = Float64Array.from({ length: N + 1 }, (_, i) => (i * L) / N);
		const exactFn = step.fn('stokes_first_solution', p);
		const exact = Float64Array.from(y, (yy) => exactFn(yy, t, U, nu) as number);
		const depth = step.fn('diffusion_depth', p)(nu, t) as number;
		// A diverged profile is not drawn at all: with only its non-finite points dropped, the two
		// boundary values would be joined into a believable-looking straight line.
		const u = f.vectors[0];
		const finite = u.every(Number.isFinite);
		shown = { y, u: finite ? u : new Float64Array(u.length).fill(NaN), exact, t, err: f.scalars[0], depth, ctx: (plan as Plan3).ctx };
	}

	let runner = createRunner({ call: (...a) => client!.call(...a), run: (o) => client!.run(o), release: (h) => client!.release(h) }, onFrame);
	let client: ReturnType<typeof createClient> | undefined;

	function planOf(ctx: Ctx, method: number): Plan3 {
		return {
			ctx,
			precision: ctx.precision,
			create: { fn: 'moving_wall', args: [ctx.N, ctx.L, ctx.U, ctx.nu] },
			advance: (sim: Handle) => ({ fn: 'advance', args: [sim, ctx.dt, STEPS_PER_FRAME, method] }),
			// advance replaces sim.u with a new vector, so the field is fetched again every frame
			vectors: (sim: Handle) => [{ fn: 'field', args: [sim] }],
			scalars: (sim: Handle) => [
				{ fn: 'moving_wall_error', args: [sim, ctx.U] },
				{ fn: 'time', args: [sim] }
			],
			frames: FRAMES,
			diverged: (f: Frame) => !Number.isFinite(f.scalars[0]) || !f.vectors[0].every(Number.isFinite)
		};
	}

	let timer: ReturnType<typeof setTimeout> | undefined;
	let current: { values: Record<string, number>; method: number; precision: Precision } | undefined;
	function restart() {
		clearTimeout(timer);
		late = undefined;
		if (!current) return;
		const v = current.values;
		const ctx: Ctx = { N: v.N, L: v.L, U: v.U, nu: v['ν'], dt: v['Δt'], precision: current.precision };
		void runner.start(planOf(ctx, current.method));
	}

	// Any control change restarts the run once the controls have been still for RESTART_MS.
	let started = false;
	$effect(() => {
		const next = { values: { ...values }, method, precision };
		if (!ready) return;
		current = next;
		clearTimeout(timer);
		if (!started) {
			started = true;
			restart();
		} else timer = setTimeout(restart, RESTART_MS);
	});

	onMount(() => {
		const worker = new Worker(new URL('../gridtopinn/worker.ts', import.meta.url), { type: 'module' });
		const c = createClient(worker);
		client = c;
		c.load(`${base}/wasm`, 3).then(
			() => (ready = true),
			(e: unknown) => (message = e instanceof Error ? e.message : String(e))
		);
		return () => {
			clearTimeout(timer);
			runner.dispose();
			worker.terminate();
		};
	});

	const stability = $derived((values['ν'] * values['Δt']) / (values.L / values.N) ** 2);
	const selectedOption = $derived(alt.options.find((o) => o.value === method) ?? alt.options[0]);
	const errorText = $derived(message || runner.error);

	const verdict = $derived.by((): { kind: 'pass' | 'fail' | 'diverged' | 'none'; text: string } => {
		if (runner.status === 'diverged') return { kind: 'diverged', text: '발산' };
		if (!shown || runner.frame === 0) return { kind: 'none', text: '계산 대기' };
		return shown.err <= PASS.step3.fractionOfU * shown.ctx.U
			? { kind: 'pass', text: '통과' }
			: { kind: 'fail', text: '기준 초과' };
	});

	const series = $derived.by((): PlotSeries[] => {
		if (!shown) return [];
		return [
			{ label: '수치해 (WASM)', role: 'primary', x: shown.y, y: shown.u },
			{ label: '해석해', role: 'reference', x: shown.y, y: shown.exact, dashed: true }
		];
	});
	// Fixed axes: the picture changes, the frame around it does not.
	const yRange = $derived({ min: -Y_MARGIN * values.U, max: (1 + Y_MARGIN) * values.U });
	const markers = $derived(shown && shown.depth > 0 && shown.depth <= shown.ctx.L ? [{ x: shown.depth, label: '확산 깊이' }] : []);
</script>

<ExperimentFrame>
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
		{#if errorText}
			<Alert.Root variant="destructive" class="mb-3" role="alert" data-testid="compute-error">
				<TriangleAlert />
				<Alert.Description>{errorText}</Alert.Description>
			</Alert.Root>
		{/if}
		<div class="mb-2 flex items-start justify-between gap-3">
			<h2 class="text-sm font-medium">벽에서 퍼져 나가는 속도 분포 u(y)</h2>
			<Verdict verdict={verdict.kind} text={verdict.text} />
		</div>
		<LinePlot {series} xLabel="y [m]" yLabel="u [m/s]" {markers} {yRange} />
		<div class="mt-3"><RunControls {runner} onreset={restart} frames={FRAMES} /></div>
	{/snippet}
	{#snippet readouts()}
		<div class="grid grid-cols-2 gap-x-4 gap-y-5 sm:grid-cols-3">
			<Readout key="time" label="시각" value={shown?.t ?? 0} unit="s" />
			<Readout key="max-error" label="해석해와의 최대 차이" value={shown?.err ?? 0} unit="m/s" />
			<Readout key="stability" label="νΔt/Δy²" value={stability} hint="명시적 방법은 0.5 부근을 넘으면 발산" />
			<Readout key="depth" label="확산 깊이" value={shown?.depth ?? 0} unit="m" />
		</div>
	{/snippet}
</ExperimentFrame>
