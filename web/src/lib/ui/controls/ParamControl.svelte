<script lang="ts">
	import Info from '@lucide/svelte/icons/info';
	import { Slider } from '$lib/components/ui/slider';
	import { Input } from '$lib/components/ui/input';
	import * as Tooltip from '$lib/components/ui/tooltip';
	import type { ParamSpec } from '$lib/gridtopinn';
	import { windowOf, type ControlSpec } from '$lib/experiments/config';
	import { formatValue } from '$lib/ui/format';
	import { SLIDER_STEPS, clamp, fromPosition, parseInput, toPosition } from './scale';

	let { spec, control, value = $bindable() }: { spec: ParamSpec; control: ControlSpec; value: number } = $props();

	const win = $derived(windowOf(spec, control));
	const scale = $derived(spec.display?.scale ?? 1);
	const unit = $derived(spec.display?.unit ?? spec.unit);
	const fmt = (v: number) => formatValue(v * scale);

	let text = $state('');
	$effect(() => {
		text = fmt(value);
	});

	// Enter fires `change` too, so commit only from `change`; a second commit would re-parse the
	// 4-significant-digit display text and round the typed value.
	function commit() {
		const parsed = parseInput(text, scale, win);
		if (parsed !== undefined) value = parsed;
		text = fmt(parsed ?? value); // an undefined parse restores the previous text
	}
</script>

<div class="flex flex-col gap-2" data-testid="param-{spec.name}" data-value={value}>
	<div class="flex items-center justify-between gap-3">
		<Tooltip.Root>
			<Tooltip.Trigger
				type="button"
				class="text-foreground hover:text-foreground/80 inline-flex min-w-0 items-center gap-1.5 text-sm"
			>
				<span class="num font-medium">{spec.name}</span>
				<span class="text-muted-foreground text-xs">[{unit}]</span>
				<Info class="text-muted-foreground size-3 shrink-0" />
			</Tooltip.Trigger>
			<Tooltip.Content>{spec.doc}</Tooltip.Content>
		</Tooltip.Root>
		<Input
			type="text"
			inputmode="decimal"
			class="num h-8 w-28 text-right text-sm md:text-sm"
			bind:value={text}
			onchange={commit}
			aria-label="{spec.name} 값 [{unit}]"
			data-testid="param-input-{spec.name}"
		/>
	</div>
	<Slider
		type="single"
		min={0}
		max={SLIDER_STEPS}
		step={1}
		value={toPosition(clamp(value, win), win)}
		onValueChange={(p: number) => (value = fromPosition(p, win))}
		thumbLabel={spec.name}
	/>
	{#if spec.presets?.length}
		<div class="flex flex-wrap gap-1.5">
			{#each spec.presets as p, i (p.label)}
				<button
					type="button"
					class="hover:bg-muted rounded-full border px-2.5 py-0.5 text-xs transition-colors"
					onclick={() => (value = clamp(p.value, win))}
					data-testid="preset-{spec.name}-{i}"
				>
					{p.label}
				</button>
			{/each}
		</div>
	{/if}
</div>
