<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import { loadIndex, type WasmIndex } from '$lib/gridtopinn';
	import StepSection from '$lib/ui/StepSection.svelte';

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
<h1>검증: 브라우저에서 실제로 도는가</h1>
{#if error}<p class="error" data-testid="error">{error}</p>{/if}
{#if index}
	{#each index.steps as entry (entry.step)}
		<StepSection {entry} {baseUrl} />
	{/each}
{:else if !error}
	<p>불러오는 중…</p>
{/if}
