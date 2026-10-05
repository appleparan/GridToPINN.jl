import { error } from '@sveltejs/kit';
import { CURRICULUM } from '$lib/curriculum';

export const entries = () => CURRICULUM.map((s) => ({ n: String(s.step) }));

export function load({ params }: { params: { n: string } }) {
	const n = Number(params.n);
	if (!CURRICULUM.some((s) => s.step === n && String(s.step) === params.n)) error(404, 'Not found');
	return { n };
}
