<script lang="ts">
	import { onMount } from 'svelte';
	import { base } from '$app/paths';
	import { page } from '$app/state';
	import Check from '@lucide/svelte/icons/check';
	import Circle from '@lucide/svelte/icons/circle';
	import Dot from '@lucide/svelte/icons/circle-dot';
	import * as Sidebar from '$lib/components/ui/sidebar';
	import { CURRICULUM } from '$lib/curriculum';
	import { ensureIndex, isAvailable } from '$lib/wasmIndex.svelte';

	const sidebar = Sidebar.useSidebar();
	const active = $derived(Number(page.params.n));

	onMount(() => void ensureIndex(`${base}/wasm`));
</script>

<Sidebar.Root>
	<Sidebar.Header class="h-14 justify-center border-b px-4">
		<a href="{base}/" class="text-base font-semibold tracking-tight">
			Grid<span class="text-primary">To</span>PINN
		</a>
	</Sidebar.Header>
	<Sidebar.Content>
		<Sidebar.Group>
			<Sidebar.GroupLabel>단계</Sidebar.GroupLabel>
			<Sidebar.Menu>
				{#each CURRICULUM as s (s.step)}
					{@const available = isAvailable(s.step)}
					{@const isActive = s.step === active}
					<Sidebar.MenuItem>
						<Sidebar.MenuButton
							{isActive}
							size="lg"
							class="h-auto items-start py-2 {available || isActive ? '' : 'opacity-60'}"
						>
							{#snippet child({ props })}
								<a
									{...props}
									href="{base}/step/{s.step}"
									data-testid="nav-step"
									data-step={s.step}
									data-available={available}
									aria-current={isActive ? 'page' : undefined}
									onclick={() => sidebar.setOpenMobile(false)}
								>
									<span class="mt-0.5 shrink-0">
										{#if isActive}
											<Dot class="text-primary" /><span class="sr-only">현재 단계</span>
										{:else if available}
											<Check class="text-primary" /><span class="sr-only">체험 가능</span>
										{:else}
											<Circle class="text-muted-foreground" /><span class="sr-only">준비 중</span>
										{/if}
									</span>
									<span class="flex min-w-0 flex-col gap-0.5 break-keep whitespace-normal! group-data-[collapsible=icon]:hidden">
										<span class="leading-snug">
											<span class="num text-muted-foreground mr-1.5">{s.step}</span>{s.title}
										</span>
										<span class="text-muted-foreground line-clamp-2 text-xs leading-snug font-normal">
											{s.question}
										</span>
									</span>
								</a>
							{/snippet}
						</Sidebar.MenuButton>
					</Sidebar.MenuItem>
				{/each}
			</Sidebar.Menu>
		</Sidebar.Group>
	</Sidebar.Content>
</Sidebar.Root>
