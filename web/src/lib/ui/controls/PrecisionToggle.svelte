<script lang="ts">
	import * as ToggleGroup from '$lib/components/ui/toggle-group';
	import type { Precision } from '$lib/gridtopinn';

	let { value = $bindable() }: { value: Precision } = $props();
</script>

<div class="flex flex-col gap-1.5">
	<span class="text-muted-foreground text-xs">정밀도</span>
	<ToggleGroup.Root
		type="single"
		variant="outline"
		size="sm"
		{value}
		onValueChange={(v) => {
			if (v === 'f64' || v === 'f32') value = v; // ignore deselection
		}}
		aria-label="정밀도"
	>
		<ToggleGroup.Item value="f64" data-testid="precision-f64" class="num px-3 data-[state=on]:bg-primary data-[state=on]:text-primary-foreground data-[state=on]:font-semibold data-[state=on]:hover:bg-primary/90">Float64</ToggleGroup.Item>
		<ToggleGroup.Item value="f32" data-testid="precision-f32" class="num px-3 data-[state=on]:bg-primary data-[state=on]:text-primary-foreground data-[state=on]:font-semibold data-[state=on]:hover:bg-primary/90">Float32</ToggleGroup.Item>
	</ToggleGroup.Root>
</div>
