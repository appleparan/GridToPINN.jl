import type { Component } from 'svelte';
import type { Step } from '$lib/gridtopinn';
import Step1 from './Step1.svelte';
import Step2 from './Step2.svelte';
import Step3 from './Step3.svelte';

/** Step number -> experiment component. Steps 4+ are added by later tasks. */
export const EXPERIMENT_COMPONENTS: Record<number, Component<{ step: Step }>> = {
	1: Step1,
	2: Step2,
	3: Step3
};
