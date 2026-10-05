<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import { loadIndex, type WasmIndex } from '$lib/gridtopinn';
	import ThemeToggle from '$lib/ui/ThemeToggle.svelte';
	import StepSection from '$lib/verify/StepSection.svelte';

	const baseUrl = `${base}/wasm`;
	let index = $state<WasmIndex | undefined>();
	let error = $state('');

	onMount(async () => {
		try {
			index = await loadIndex(baseUrl);
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
	});
</script>

<svelte:head><title>검증 — GridToPINN</title></svelte:head>
<header class="mx-auto flex h-14 w-full max-w-5xl items-center justify-between px-4">
	<a href="{base}/" class="text-base font-semibold tracking-tight">
		Grid<span class="text-primary">To</span>PINN
	</a>
	<ThemeToggle />
</header>
<div class="verify-page mx-auto max-w-5xl space-y-6 p-4">
<h1 class="text-2xl font-semibold tracking-tight">검증: 브라우저에서 실제로 도는가</h1>
<p class="text-sm text-muted-foreground">
	이 페이지는 브라우저 WASM 결과가 네이티브 Julia와 같은지 확인합니다. 체험은 각 단계 화면에서 합니다.
	<a href="{base}/" class="text-primary underline underline-offset-4">처음으로</a>
</p>
{#if error}<p class="error" data-testid="error">{error}</p>{/if}
{#if index}
	{#each index.steps as entry (entry.step)}
		<StepSection {entry} {baseUrl} />
	{/each}
{:else if !error}
	<p>불러오는 중…</p>
{/if}
</div>
