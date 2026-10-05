<script lang="ts">
	import { base } from '$app/paths';
	import * as Sidebar from '$lib/components/ui/sidebar';
	import ThemeToggle from '$lib/ui/ThemeToggle.svelte';
	import { Button } from '$lib/components/ui/button';

	let { title }: { title: string } = $props();
</script>

<header
	class="bg-background/80 sticky top-0 z-20 flex h-14 items-center gap-3 border-b px-4 backdrop-blur"
>
	<Sidebar.Trigger aria-label="단계 목록" />
	<span class="truncate text-sm font-medium" data-testid="topbar-title">{title}</span>
	<div class="ml-auto flex items-center gap-1">
		<Button variant="ghost" size="sm" href="{base}/verify" data-testid="verify-link">검증</Button>
		<ThemeToggle />
	</div>
</header>
