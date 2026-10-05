<script lang="ts">
	import { formatValue } from './format';

	let { key, label, value, unit, hint }: { key: string; label: string; value: number; unit?: string; hint?: string } =
		$props();
</script>

<div class="flex min-w-0 flex-col gap-1" data-testid="readout-{key}" data-value={String(value)} title={hint}>
	<span class="text-muted-foreground text-xs leading-tight">{label}</span>
	<span class="flex items-baseline gap-1">
		<span class="num text-xl font-medium tracking-tight">{formatValue(value)}</span>
		{#if unit}<span class="text-muted-foreground text-xs">{unit}</span>{/if}
	</span>
</div>
