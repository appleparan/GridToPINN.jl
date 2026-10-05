<script lang="ts">
	import Play from '@lucide/svelte/icons/play';
	import Pause from '@lucide/svelte/icons/pause';
	import RotateCcw from '@lucide/svelte/icons/rotate-ccw';
	import { Button } from '$lib/components/ui/button';
	import type { Runner, RunStatus } from '$lib/experiments/runner.svelte';

	let { runner, onreset, frames }: { runner: Runner; onreset: () => void; frames: number } = $props();

	const LABEL: Record<RunStatus, string> = {
		idle: '대기',
		running: '계산 중',
		paused: '일시정지',
		done: '완료',
		diverged: '발산',
		error: '오류'
	};
	const canPlay = $derived(runner.status === 'paused' || runner.status === 'done');
</script>

<div class="flex flex-wrap items-center gap-2" role="group" aria-label="실행 제어">
	{#if runner.status === 'running'}
		<Button size="sm" variant="outline" onclick={() => runner.pause()} data-testid="run-pause">
			<Pause /> 일시정지
		</Button>
	{:else}
		<Button
			size="sm"
			variant="outline"
			disabled={!canPlay}
			onclick={() => (runner.status === 'done' ? onreset() : runner.resume())}
			data-testid="run-play"
		>
			<Play /> {runner.status === 'done' ? '다시 재생' : '재생'}
		</Button>
	{/if}
	<Button size="sm" variant="outline" onclick={onreset} data-testid="run-reset"><RotateCcw /> 처음부터</Button>
	<span class="text-muted-foreground ml-auto flex items-center gap-3 text-sm">
		<span data-testid="run-status" data-status={runner.status} aria-live="polite">{LABEL[runner.status]}</span>
		<span class="num" data-testid="frame-counter">{runner.frame} / {frames}</span>
	</span>
</div>
