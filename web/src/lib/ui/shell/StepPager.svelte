<script lang="ts">
	import { base } from '$app/paths';
	import ArrowLeft from '@lucide/svelte/icons/arrow-left';
	import ArrowRight from '@lucide/svelte/icons/arrow-right';
	import { CURRICULUM } from '$lib/curriculum';

	let { step }: { step: number } = $props();
	const prev = $derived(CURRICULUM.find((s) => s.step === step - 1));
	const next = $derived(CURRICULUM.find((s) => s.step === step + 1));
	const link =
		'text-muted-foreground hover:text-foreground flex items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors';
</script>

<nav class="mt-12 flex items-center justify-between border-t pt-4" aria-label="단계 이동">
	{#if prev}
		<a class={link} href="{base}/step/{prev.step}" data-testid="prev-step">
			<ArrowLeft class="size-4" />
			<span><span class="num">{prev.step}</span> {prev.title}</span>
		</a>
	{:else}<span></span>{/if}
	{#if next}
		<a class={link} href="{base}/step/{next.step}" data-testid="next-step">
			<span><span class="num">{next.step}</span> {next.title}</span>
			<ArrowRight class="size-4" />
		</a>
	{/if}
</nav>
