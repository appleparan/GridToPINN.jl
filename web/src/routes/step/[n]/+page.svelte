<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import Hourglass from '@lucide/svelte/icons/hourglass';
	import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
	import * as Alert from '$lib/components/ui/alert';
	import { Skeleton } from '$lib/components/ui/skeleton';
	import { CURRICULUM } from '$lib/curriculum';
	import { loadStep, type Step } from '$lib/gridtopinn';
	import { EXPERIMENT_COMPONENTS } from '$lib/experiments/registry';
	import { ensureIndex, isAvailable, wasmIndex } from '$lib/wasmIndex.svelte';
	import StepPager from '$lib/ui/shell/StepPager.svelte';

	let { data } = $props();
	const info = $derived(CURRICULUM.find((s) => s.step === data.n)!);

	let loaded = $state<{ n: number; step?: Step; error?: string }>();
	const Experiment = $derived(EXPERIMENT_COMPONENTS[data.n]);
	const indexReady = $derived(wasmIndex.value !== undefined);

	onMount(() => {
		void ensureIndex(`${base}/wasm`);
	});

	// Load the wasm module once the index says the step exists and a component is registered.
	$effect(() => {
		const n = data.n;
		if (!indexReady || !isAvailable(n) || !EXPERIMENT_COMPONENTS[n]) return;
		let stale = false;
		loadStep(`${base}/wasm`, n).then(
			(step) => !stale && (loaded = { n, step }),
			(e: unknown) => !stale && (loaded = { n, error: e instanceof Error ? e.message : String(e) })
		);
		return () => {
			stale = true;
		};
	});

	const current = $derived(loaded?.n === data.n ? loaded : undefined);
	const comingSoon = $derived(indexReady && (!isAvailable(data.n) || !Experiment));
	const failure = $derived(wasmIndex.error || current?.error || '');
</script>

<svelte:head><title>{info.step}단계 · {info.title} — GridToPINN</title></svelte:head>

{#key data.n}
	<div class="mx-auto w-full max-w-[88rem] px-4 py-8 sm:px-6 lg:py-10">
		<h1 class="text-2xl font-semibold tracking-tight sm:text-3xl" data-testid="step-title">
			{info.step}단계 · {info.title}
		</h1>
		<p class="text-muted-foreground mt-3 max-w-2xl text-lg leading-relaxed break-keep" data-testid="step-question">
			{info.question}
		</p>

		{#if failure}
			<Alert.Root variant="destructive" class="mt-8" role="alert" data-testid="load-error">
				<TriangleAlert />
				<Alert.Title>이 단계를 불러오지 못했습니다</Alert.Title>
				<Alert.Description>
					<p class="num break-all">{failure}</p>
					<p class="mt-1">WebAssembly GC를 지원하는 최신 브라우저가 필요합니다.</p>
				</Alert.Description>
			</Alert.Root>
		{:else if comingSoon}
			<div
				class="text-muted-foreground mt-10 flex items-center gap-3 rounded-xl border border-dashed p-6 text-sm"
				data-testid="coming-soon"
			>
				<Hourglass class="size-4 shrink-0" />
				<span>준비 중입니다. 이 단계의 체험 화면은 아직 없습니다.</span>
			</div>
		{:else if current?.step && Experiment}
			<Experiment step={current.step} />
		{:else}
			<div class="mt-8 grid gap-6 xl:grid-cols-2" aria-busy="true" aria-label="불러오는 중">
				<Skeleton class="h-96 rounded-xl" />
				<Skeleton class="h-96 rounded-xl" />
			</div>
		{/if}
		<StepPager step={info.step} />
	</div>
{/key}
