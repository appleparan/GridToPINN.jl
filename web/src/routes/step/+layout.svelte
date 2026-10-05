<script lang="ts">
	import { page } from '$app/state';
	import * as Sidebar from '$lib/components/ui/sidebar';
	import { CURRICULUM } from '$lib/curriculum';
	import AppSidebar from '$lib/ui/shell/AppSidebar.svelte';
	import TopBar from '$lib/ui/shell/TopBar.svelte';

	let { children } = $props();
	const current = $derived(CURRICULUM.find((s) => String(s.step) === page.params.n));
</script>

<Sidebar.Provider>
	<AppSidebar />
	<Sidebar.Inset class="min-w-0">
		<TopBar title={current ? `${current.step}단계 · ${current.title}` : ''} />
		{@render children()}
	</Sidebar.Inset>
</Sidebar.Provider>
