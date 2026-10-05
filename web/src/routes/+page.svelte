<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import Check from '@lucide/svelte/icons/check';
	import Hourglass from '@lucide/svelte/icons/hourglass';
	import { Badge } from '$lib/components/ui/badge';
	import { Button } from '$lib/components/ui/button';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import { CURRICULUM } from '$lib/curriculum';
	import ThemeToggle from '$lib/ui/ThemeToggle.svelte';
	import { ensureIndex, isAvailable, wasmIndex } from '$lib/wasmIndex.svelte';

	const loaded = $derived(wasmIndex.value !== undefined || wasmIndex.error !== '');
	const card =
		'bg-card text-card-foreground ring-foreground/10 flex h-full flex-col gap-3 rounded-xl p-5 ring-1 transition-shadow';

	onMount(() => void ensureIndex(`${base}/wasm`));
</script>

<svelte:head><title>GridToPINN</title></svelte:head>

<header class="mx-auto flex h-14 w-full max-w-6xl items-center justify-between px-4 sm:px-6">
	<a href="{base}/" class="text-base font-semibold tracking-tight">
		Grid<span class="text-primary">To</span>PINN
	</a>
	<div class="flex items-center gap-1">
		<Button variant="ghost" size="sm" href="{base}/verify" data-testid="verify-link">검증</Button>
		<ThemeToggle />
	</div>
</header>

<main class="mx-auto w-full max-w-6xl px-4 pb-20 sm:px-6">
	<section class="py-12 sm:py-16">
		<h1 class="text-4xl font-semibold tracking-tight sm:text-5xl">GridToPINN</h1>
		<p class="text-muted-foreground mt-4 max-w-xl break-keep text-lg leading-relaxed">
			CFD를 밑바닥부터 짜서 PINN까지. 화면에 보이는 Julia 코드가 브라우저에서 그대로 돕니다. 숫자를 끌어
			보세요.
		</p>
	</section>

	<ol class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
		{#each CURRICULUM as s (s.step)}
			{@const available = isAvailable(s.step)}
			<li>
				{#snippet body()}
					<div class="flex items-start justify-between gap-3">
						<span class="num text-muted-foreground text-4xl leading-none font-medium">{s.step}</span>
						{#if !loaded}
							<Skeleton class="h-5 w-16 rounded-4xl" />
						{:else if available}
							<Badge><Check />체험 가능</Badge>
						{:else}
							<Badge variant="secondary"><Hourglass />준비 중</Badge>
						{/if}
					</div>
					<h2 class="text-lg leading-snug font-semibold">{s.title}</h2>
					<p class="text-sm leading-relaxed break-keep">{s.question}</p>
					<p class="text-muted-foreground mt-auto pt-2 text-xs">{s.method}</p>
				{/snippet}
				{#if available}
					<a
						href="{base}/step/{s.step}"
						class="{card} hover:ring-primary/50 focus-visible:ring-primary hover:shadow-md focus-visible:outline-none focus-visible:ring-2"
						data-testid="step-card"
						data-step={s.step}
						data-available="true"
					>
						{@render body()}
					</a>
				{:else}
					<div
						class="{card} {loaded ? 'opacity-60' : ''}"
						aria-disabled="true"
						data-testid="step-card"
						data-step={s.step}
						data-available="false"
					>
						{@render body()}
					</div>
				{/if}
			</li>
		{/each}
	</ol>
	{#if wasmIndex.error}
		<p class="text-destructive mt-6 text-sm" data-testid="load-error">{wasmIndex.error}</p>
	{/if}
</main>
