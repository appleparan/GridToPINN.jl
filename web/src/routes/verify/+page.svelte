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
<div class="verify-page mx-auto max-w-5xl p-4">
<h1>검증: 브라우저에서 실제로 도는가</h1>
{#if error}<p class="error" data-testid="error">{error}</p>{/if}
{#if index}
	{#each index.steps as entry (entry.step)}
		<StepSection {entry} {baseUrl} />
	{/each}
{:else if !error}
	<p>불러오는 중…</p>
{/if}
</div>
