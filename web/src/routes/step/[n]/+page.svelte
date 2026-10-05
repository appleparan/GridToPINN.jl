<script lang="ts">
	import Hourglass from '@lucide/svelte/icons/hourglass';
	import { CURRICULUM } from '$lib/curriculum';
	import StepPager from '$lib/ui/shell/StepPager.svelte';

	let { data } = $props();
	const step = $derived(CURRICULUM.find((s) => s.step === data.n)!);
</script>

<svelte:head><title>{step.step}단계 · {step.title} — GridToPINN</title></svelte:head>

{#key data.n}
	<div class="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6 lg:py-12">
		<h1 class="text-2xl font-semibold tracking-tight sm:text-3xl" data-testid="step-title">
			{step.step}단계 · {step.title}
		</h1>
		<p class="text-muted-foreground mt-3 max-w-2xl break-keep text-lg leading-relaxed" data-testid="step-question">
			{step.question}
		</p>
		<div
			class="text-muted-foreground mt-10 flex items-center gap-3 rounded-xl border border-dashed p-6 text-sm"
			data-testid="coming-soon"
		>
			<Hourglass class="size-4 shrink-0" />
			<span>준비 중입니다. 이 단계의 체험 화면은 아직 없습니다.</span>
		</div>
		<StepPager step={step.step} />
	</div>
{/key}
