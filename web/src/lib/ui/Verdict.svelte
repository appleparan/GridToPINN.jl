<script lang="ts">
	import Check from '@lucide/svelte/icons/check';
	import X from '@lucide/svelte/icons/x';
	import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
	import Minus from '@lucide/svelte/icons/minus';
	import { Badge } from '$lib/components/ui/badge';

	type Kind = 'pass' | 'fail' | 'diverged' | 'none';
	let { verdict, text }: { verdict: Kind; text: string } = $props();

	const variant = $derived(verdict === 'pass' ? 'default' : verdict === 'none' ? 'secondary' : 'destructive');
</script>

<Badge {variant} class="h-6 gap-1.5 px-2.5 text-sm" data-testid="verdict" data-verdict={verdict}>
	{#if verdict === 'pass'}<Check />{:else if verdict === 'fail'}<X />{:else if verdict === 'diverged'}<TriangleAlert
		/>{:else}<Minus />{/if}
	{text}
</Badge>
