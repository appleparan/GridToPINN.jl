<script lang="ts">
	import { sourceText } from '$lib/sources';
	import type { SourceRange } from '$lib/gridtopinn';
	import { highlight } from './highlight';

	let { source, label, optionKey }: { source: SourceRange; label: string; optionKey: string } = $props();

	const loaded = $derived.by(() => {
		try {
			return { text: sourceText(source), error: '' };
		} catch (e) {
			return { text: '', error: e instanceof Error ? e.message : String(e) };
		}
	});

	let html = $state('');
	$effect(() => {
		const code = loaded.text;
		html = '';
		if (!code) return;
		let stale = false;
		highlight(code).then(
			(h) => {
				if (!stale) html = h;
			},
			() => {} // highlighting is cosmetic; the plain text stays
		);
		return () => {
			stale = true;
		};
	});
</script>

<div
	class="bg-card overflow-hidden rounded-xl border"
	data-testid="code-panel"
	data-file={source.file}
	data-lines="{source.lines[0]}-{source.lines[1]}"
	data-key={optionKey}
>
	<div class="bg-muted/50 flex items-center justify-between gap-3 border-b px-3 py-2">
		<span class="truncate text-sm font-medium">{label}</span>
		<span class="num text-muted-foreground shrink-0 text-xs">{source.file}:{source.lines[0]}–{source.lines[1]}</span>
	</div>
	{#if loaded.error}
		<p class="text-destructive p-3 text-sm" role="alert">{loaded.error}</p>
	{:else if html}
		<!-- html comes from shiki over this repository's own .jl files only -->
		<div class="code-body max-h-[22rem] overflow-auto">{@html html}</div>
	{:else}
		<div class="code-body max-h-[22rem] overflow-auto"><pre class="shiki">{loaded.text}</pre></div>
	{/if}
</div>

<style>
	.code-body :global(pre) {
		margin: 0;
		padding: 0.75rem 0.875rem;
		font-family: var(--font-mono);
		font-size: 0.8125rem;
		line-height: 1.6;
		width: max-content;
		min-width: 100%;
		tab-size: 4;
	}
	.code-body :global(code) {
		font-family: inherit;
	}
</style>
