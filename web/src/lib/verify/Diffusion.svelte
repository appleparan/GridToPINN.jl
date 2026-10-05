<script lang="ts">
	// 3단계: 계산을 전부 Worker에서 돌리고, 프레임이 올 때마다 u(y)를 그린다.
	import { onMount } from 'svelte';
	import { createClient, type Client, type Frame, type Handle, type Precision, type Step } from '$lib/gridtopinn';
	import { drawPlot } from './plot';

	let { step, baseUrl }: { step: Step; baseUrl: string } = $props();

	const N = 100, L = 0.1, U = 1, NU = 1e-5, DT = 0.01, STEPS_PER_FRAME = 100, FRAMES = 30;
	const alt = $derived(step.manifest.alternatives.find((a) => a.id === 'integrator')!);

	let precision = $state<Precision>('f64');
	let method = $state(0);
	let frame = $state(0);
	let status = $state('대기');
	let error = $state('');
	let finalError = $state('');
	let plotError = $state('');
	let canvas: HTMLCanvasElement;
	let client: Client | undefined;
	let current: { stop(): Promise<void>; done: Promise<unknown> } | undefined;
	let runToken = 0;

	async function start() {
		const token = ++runToken;
		if (current) {
			await current.stop().catch(() => {});
			await current.done.catch(() => {});
		}
		if (token !== runToken || !client) return;
		frame = 0; status = '계산 중'; error = ''; finalError = ''; plotError = '';
		const p = precision, m = method;
		const c = client;
		let sim: Handle | undefined;
		try {
			sim = (await c.call('moving_wall', p, [N, L, U, NU])) as Handle;
			const y = Float64Array.from({ length: N + 1 }, (_, i) => (i * L) / N);
			const exactFn = step.fn('stokes_first_solution', p);
			const run = c.run({
				fn: 'advance', precision: p, args: [sim, DT, STEPS_PER_FRAME, m], frames: FRAMES,
				// 장은 프레임마다 field(sim)으로 다시 꺼낸다: advance가 sim.u를 새 벡터로 바꾸므로
				// 전진하기 전에 받아 둔 참조는 옛 장(초기조건)을 가리킨다.
				vectors: [{ fn: 'field', args: [sim] }],
				scalars: [{ fn: 'moving_wall_error', args: [sim, U] }, { fn: 'time', args: [sim] }],
				onFrame: (f: Frame) => {
					if (token !== runToken) return;
					const t = f.scalars[1];
					frame = f.frame;
					finalError = f.scalars[0].toExponential(6);
					const exact = Array.from(y, (yy) => exactFn(yy, t, U, NU) as number);
					// 그린 곡선과 해석해의 최대 차이. 커널이 보고한 오차와 같아야 한다 (e2e가 확인).
					const drawn = f.vectors[0];
					plotError = exact.reduce((mx, ex, i) => Math.max(mx, Math.abs(drawn[i] - ex)), 0).toExponential(6);
					drawPlot(canvas, [
						{ label: 'Worker (WASM)', color: '#05c', x: y, y: f.vectors[0] },
						{ label: '해석해', color: '#c50', x: y, y: exact }
					], { xlabel: 'y [m]', ylabel: 'u [m/s]' });
				}
			});
			current = run;
			const r = (await run.done) as { stopped: boolean };
			if (token === runToken) status = r.stopped ? '중단' : '완료';
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
			status = '오류';
		} finally {
			if (sim && client) await client.release([sim]).catch(() => {});
		}
	}

	onMount(() => {
		const worker = new Worker(new URL('../gridtopinn/worker.ts', import.meta.url), { type: 'module' });
		method = alt.options[0].value;
		client = createClient(worker);
		client.load(baseUrl, step.manifest.step).then(start, (e) => {
			error = String(e instanceof Error ? e.message : e);
			status = '오류';
		});
		return () => { runToken++; worker.terminate(); };
	});
</script>

<div class="live">
	<h4>Worker 실시간 실행 (벽 속도 {U} m/s, ν = {NU} m²/s, Δt = {DT} s)</h4>
	<label>적분기
		<select data-testid="integrator" value={method} onchange={(e) => { method = Number(e.currentTarget.value); start(); }}>
			{#each alt.options as o (o.value)}<option value={o.value}>{o.label}</option>{/each}
		</select>
	</label>
	<label>정밀도
		<select data-testid="precision" value={precision} onchange={(e) => { precision = e.currentTarget.value as Precision; start(); }}>
			<option value="f64">Float64</option><option value="f32">Float32</option>
		</select>
	</label>
	<p>
		프레임 <span data-testid="frame-counter">{frame}</span> / <span data-testid="frame-total">{FRAMES}</span>,
		상태 <span data-testid="step3-status">{status}</span>,
		현재 오차 <span data-testid="step3-error">{finalError}</span>,
		그린 곡선의 오차 <span data-testid="step3-plot-error">{plotError}</span>
	</p>
	{#if error}<p class="error" data-testid="error">Worker 오류: {error}</p>{/if}
	<canvas data-testid="plot-3-live" bind:this={canvas} width="560" height="260"></canvas>
</div>
