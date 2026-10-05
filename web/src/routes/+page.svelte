<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import { loadIndex, type WasmIndex } from '$lib/gridtopinn';
	import ThemeToggle from '$lib/ui/ThemeToggle.svelte';

	let index = $state<WasmIndex | undefined>();
	let questions = $state<Record<number, string>>({});
	let error = $state('');

	onMount(async () => {
		try {
			const baseUrl = `${base}/wasm`;
			index = await loadIndex(baseUrl);
			for (const s of index.steps) {
				const res = await fetch(`${baseUrl}/${s.manifest}`);
				if (!res.ok) throw new Error(`GET ${baseUrl}/${s.manifest} 실패: HTTP ${res.status}`);
				questions[s.step] = ((await res.json()) as { question: string }).question;
			}
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
	});
</script>

<svelte:head><title>GridToPINN</title></svelte:head>
<header class="mx-auto flex max-w-5xl items-center justify-between p-4">
	<nav><a href="{base}/">처음</a> · <a href="{base}/verify">검증</a></nav>
	<ThemeToggle />
</header>
<div class="mx-auto max-w-5xl p-4">
<h1>GridToPINN — 계산 커널 검증 사이트</h1>
<p>Julia 커널을 WebAssembly로 컴파일해 브라우저에서 그대로 실행합니다. 꾸밈 없는 시험 페이지입니다.</p>
{#if error}<p class="error" data-testid="error">{error}</p>{/if}
{#if index}
	<ul>
		{#each index.steps as s (s.step)}
			<li data-testid="step-row">
				<strong>{s.step}단계 {s.title}</strong> — {questions[s.step] ?? ''}
				({(s.bytes / 1024).toFixed(1)} KiB) · <a href="{base}/verify#step{s.step}">검증</a>
			</li>
		{/each}
	</ul>
	<p><a data-testid="verify-link" href="{base}/verify">모든 단계 검증하기</a></p>
{:else if !error}
	<p>불러오는 중…</p>
{/if}
</div>
