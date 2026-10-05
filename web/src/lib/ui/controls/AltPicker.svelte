<script lang="ts">
	import * as ToggleGroup from '$lib/components/ui/toggle-group';
	import type { AltSpec } from '$lib/gridtopinn';

	let { alt, value = $bindable() }: { alt: AltSpec; value: number } = $props();
	const selected = $derived(alt.options.find((o) => o.value === value) ?? alt.options[0]);
</script>

<div class="flex flex-col gap-1.5" data-testid="alt-{alt.id}" data-value={selected.key}>
	<span class="text-muted-foreground text-xs">{alt.title}</span>
	<ToggleGroup.Root
		type="single"
		variant="outline"
		size="sm"
		class="flex-wrap"
		value={selected.key}
		onValueChange={(k) => {
			const o = alt.options.find((q) => q.key === k);
			if (o) value = o.value; // ignore deselection: value never becomes empty
		}}
		aria-label={alt.title}
	>
		{#each alt.options as o (o.key)}
			<ToggleGroup.Item value={o.key} data-testid="alt-option-{o.key}" class="px-3 data-[state=on]:bg-primary data-[state=on]:text-primary-foreground data-[state=on]:font-semibold data-[state=on]:hover:bg-primary/90">{o.label}</ToggleGroup.Item>
		{/each}
	</ToggleGroup.Root>
</div>
