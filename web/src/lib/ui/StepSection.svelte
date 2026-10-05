<script lang="ts">
	import { onMount } from 'svelte';
	import { loadParity, loadStep, runParity, type CaseResult, type IndexStep, type Precision, type Step } from '$lib/gridtopinn';
	import { sourceText } from '$lib/sources';
	import { demoStep1, demoStep2 } from './demos';
	import Diffusion from './Diffusion.svelte';

	let { entry, baseUrl }: { entry: IndexStep; baseUrl: string } = $props();

	let step = $state<Step | undefined>();
	let results = $state<CaseResult[]>([]);
	let note = $state('');
	let error = $state('');
	let canvas = $state<HTMLCanvasElement | undefined>();

	const summary = (p: Precision) => {
		const rs = results.filter((r) => r.precision === p);
		return { cases: rs.length, failures: rs.filter((r) => !r.pass).length, ops: rs.reduce((n, r) => n + r.ops.length, 0) };
	};
	const snippet = (o: { source: { file: string; lines: [number, number] } }) => {
		try { return sourceText(o.source); } catch (e) { error = String(e instanceof Error ? e.message : e); return ''; }
	};

	onMount(async () => {
		try {
			const s = await loadStep(baseUrl, entry.step);
			step = s;
			results = runParity(s, await loadParity(baseUrl, entry.step));
			// canvas는 step이 정해진 뒤 렌더링되므로 한 틱 뒤에 그린다
			await Promise.resolve();
			if (entry.step === 1 && canvas) note = demoStep1(s, canvas);
			if (entry.step === 2 && canvas) note = demoStep2(s, canvas);
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
	});
</script>

<section data-testid="step-section" data-step={entry.step}>
	<h2>{entry.step}단계 — {entry.title}</h2>
	{#if error}<p class="error" data-testid="error">{error}</p>{/if}
	{#if step}
		<p>{step.manifest.question}</p>

		<h3>패리티 (Julia 네이티브 결과와 브라우저 WASM 결과)</h3>
		{#each ['f64', 'f32'] as const as p (p)}
			{@const s = summary(p)}
			<p data-testid="parity-summary" data-step={entry.step} data-precision={p} data-cases={s.cases} data-failures={s.failures}>
				{p}: 사례 {s.cases}개, 비교 {s.ops}건, 실패 {s.failures}건
			</p>
		{/each}
		<details>
			<summary>사례별 결과</summary>
			<table>
				<thead><tr><th>사례</th><th>정밀도</th><th>비교 수</th><th>결과</th><th>최대 상대차</th></tr></thead>
				<tbody>
					{#each results as r, i (i)}
						<tr data-testid="parity-row" class={r.pass ? 'pass' : 'fail'}>
							<td>{r.name}</td><td>{r.precision}</td><td>{r.ops.length}</td>
							<td>{r.pass ? '통과' : '실패'}</td><td>{r.maxRelDiff.toExponential(2)}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</details>

		<h3>그림 (WASM 호출로 계산)</h3>
		{#if entry.step === 3}
			<Diffusion {step} {baseUrl} />
		{:else}
			<canvas data-testid="plot-{entry.step}" bind:this={canvas} width="560" height="260"></canvas>
			<p data-testid="plot-note-{entry.step}">{note}</p>
		{/if}

		<h3>내보낸 함수</h3>
		<ul>
			{#each step.manifest.functions as f (f.name)}
				<li data-testid="fn-row"><code>{f.name}({f.args.map((a) => `${a.name}: ${a.type}`).join(', ')})</code> → {f.returns} — {f.doc}</li>
			{/each}
		</ul>

		<h3>조작 값</h3>
		<table>
			<thead><tr><th>이름</th><th>단위</th><th>기본값</th><th>범위</th></tr></thead>
			<tbody>
				{#each step.manifest.parameters as p (p.name)}
					<tr data-testid="param-row"><td>{p.name}</td><td>{p.unit}</td><td>{p.default}</td><td>{p.min} ~ {p.max}</td></tr>
				{/each}
			</tbody>
		</table>

		<h3>대안 (화면에 보이는 코드 = 컴파일된 코드)</h3>
		{#each step.manifest.alternatives as a (a.id)}
			<h4>{a.title} (인자 <code>{a.arg}</code>)</h4>
			{#each a.options as o (o.value)}
				<details open>
					<summary>{o.label} — {a.arg}={o.value}, {o.source.file}:{o.source.lines[0]}–{o.source.lines[1]}</summary>
					<pre data-testid="alt-source" data-key={o.key}>{snippet(o)}</pre>
				</details>
			{/each}
		{/each}
	{:else if !error}
		<p>불러오는 중…</p>
	{/if}
</section>
