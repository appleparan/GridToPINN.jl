<script lang="ts">
	import Play from '@lucide/svelte/icons/play';
	import Pause from '@lucide/svelte/icons/pause';
	import RotateCcw from '@lucide/svelte/icons/rotate-ccw';
	import { Button } from '$lib/components/ui/button';
	import type { Playback, PlaybackStatus } from '$lib/experiments/playback.svelte';

	let { playback }: { playback: Playback } = $props();

	const LABEL: Record<PlaybackStatus, string> = { playing: '재생 중', paused: '일시정지', done: '완료' };
</script>

<div class="flex flex-col gap-2" role="group" aria-label="재생 제어">
	<div class="flex flex-wrap items-center gap-2">
		{#if playback.status === 'playing'}
			<Button size="sm" variant="outline" onclick={() => playback.pause()} data-testid="play-pause">
				<Pause /> 일시정지
			</Button>
		{:else}
			<Button size="sm" variant="outline" onclick={() => playback.play()} data-testid="play-play">
				<Play /> {playback.status === 'done' ? '다시 재생' : '재생'}
			</Button>
		{/if}
		<Button size="sm" variant="outline" onclick={() => playback.restart()} data-testid="play-restart">
			<RotateCcw /> 처음부터
		</Button>
		<span class="text-muted-foreground ml-auto text-sm" data-testid="play-status" data-status={playback.status} aria-live="polite">
			{LABEL[playback.status]}
		</span>
	</div>
	<div
		class="bg-muted h-1 w-full overflow-hidden rounded-full"
		role="progressbar"
		aria-label="재생 진행"
		aria-valuemin="0"
		aria-valuemax="100"
		aria-valuenow={Math.round(playback.progress * 100)}
		data-testid="play-progress"
	>
		<div class="bg-primary h-full" style:width="{playback.progress * 100}%"></div>
	</div>
</div>
