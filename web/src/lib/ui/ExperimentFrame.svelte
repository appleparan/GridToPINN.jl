<script lang="ts">
	import type { Snippet } from 'svelte';
	import * as Tooltip from '$lib/components/ui/tooltip';

	let {
		controls,
		code,
		plot,
		readouts,
		computeMs
	}: {
		controls: Snippet;
		code: Snippet;
		plot: Snippet;
		readouts: Snippet;
		computeMs?: number;
	} = $props();
</script>

<Tooltip.Provider delayDuration={200}>
	<!-- Single column (plot first) below xl; two columns from xl, the plot column sticks while the left one scrolls. -->
	<div
		class="mt-8 grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] xl:items-start"
		data-testid="experiment"
		data-compute-ms={computeMs === undefined ? undefined : computeMs.toFixed(2)}
	>
		<div class="order-2 flex min-w-0 flex-col gap-6 xl:order-1">
			{@render code()}
			{@render controls()}
		</div>
		<div class="order-1 flex min-w-0 flex-col gap-4 xl:sticky xl:top-20 xl:order-2">
			<div class="bg-card rounded-xl border p-4">
				{@render plot()}
			</div>
			<div class="bg-card rounded-xl border p-4">
				{@render readouts()}
			</div>
		</div>
	</div>
</Tooltip.Provider>
