// Display-only thinning of long series: keep, per x bucket, the first sample, the min, the max, any
// non-finite sample, and always the last sample, so spikes, gaps and the playback head survive.
// The experiments' readouts keep using the full arrays.
export function decimate(x: ArrayLike<number>, y: ArrayLike<number>, maxPoints: number): { x: number[]; y: number[] } {
	const n = Math.min(x.length, y.length);
	if (n <= maxPoints) return { x: Array.from(x), y: Array.from(y) };
	const buckets = Math.max(1, Math.floor(maxPoints / 4));
	const keep = new Set<number>([0, n - 1]);
	for (let b = 0; b < buckets; b++) {
		const lo = Math.floor((b * n) / buckets);
		const hi = Math.floor(((b + 1) * n) / buckets);
		if (hi <= lo) continue;
		keep.add(lo);
		let iMin = -1;
		let iMax = -1;
		for (let i = lo; i < hi; i++) {
			const v = y[i];
			if (!Number.isFinite(v)) {
				keep.add(i);
				continue;
			}
			if (iMin < 0 || v < y[iMin]) iMin = i;
			if (iMax < 0 || v > y[iMax]) iMax = i;
		}
		if (iMin >= 0) keep.add(iMin);
		if (iMax >= 0) keep.add(iMax);
	}
	const idx = [...keep].sort((a, b) => a - b);
	return { x: idx.map((i) => x[i]), y: idx.map((i) => y[i]) };
}
