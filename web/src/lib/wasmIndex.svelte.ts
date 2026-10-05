// One fetch of index.json shared by the home page, the sidebar and the step pages.
import { loadIndex, type WasmIndex } from '$lib/gridtopinn';

export const wasmIndex = $state<{ value: WasmIndex | undefined; error: string }>({
	value: undefined,
	error: ''
});

let pending: Promise<void> | undefined;

/** Idempotent. Fills `wasmIndex.value` or `wasmIndex.error`. Call from onMount only. */
export function ensureIndex(baseUrl: string): Promise<void> {
	pending ??= loadIndex(baseUrl).then(
		(index) => {
			wasmIndex.value = index;
			wasmIndex.error = '';
		},
		(e: unknown) => {
			wasmIndex.error = e instanceof Error ? e.message : String(e);
			pending = undefined; // allow a retry on the next call
		}
	);
	return pending;
}

/** False until the index has loaded. */
export function isAvailable(step: number): boolean {
	return wasmIndex.value?.steps.some((s) => s.step === step) ?? false;
}
