import type { Component } from 'svelte';
import type { Step } from '$lib/gridtopinn';
import Step1 from './Step1.svelte';

/** Step number -> experiment component. Steps 2 and 3 are added by later tasks. */
export const EXPERIMENT_COMPONENTS: Record<number, Component<{ step: Step }>> = {
	1: Step1
};
