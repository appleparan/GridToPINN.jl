// Display-only helpers for playback: show a prefix of kernel-computed samples. The only arithmetic is
// the linear interpolation of one head point between two samples the kernel already produced.

/** Samples with x <= xCut, plus one interpolated point at xCut when it falls between two samples. x ascending. */
export function revealUpTo(x: ArrayLike<number>, y: ArrayLike<number>, xCut: number): { x: number[]; y: number[] } {
	const n = Math.min(x.length, y.length);
	// binary search: number of samples with x <= xCut
	let lo = 0;
	let hi = n;
	while (lo < hi) {
		const mid = (lo + hi) >>> 1;
		if (x[mid] <= xCut) lo = mid + 1;
		else hi = mid;
	}
	const k = lo;
	const outX = Array.from({ length: k }, (_, i) => x[i]);
	const outY = Array.from({ length: k }, (_, i) => y[i]);
	if (k > 0 && k < n && x[k - 1] < xCut) {
		const [x0, x1, y0, y1] = [x[k - 1], x[k], y[k - 1], y[k]];
		if (Number.isFinite(y0) && Number.isFinite(y1)) {
			outX.push(xCut);
			outY.push(y0 + ((y1 - y0) * (xCut - x0)) / (x1 - x0));
		}
	}
	return { x: outX, y: outY };
}

/** The first `count` samples (count clamped to [0, length]). */
export function revealCount(x: ArrayLike<number>, y: ArrayLike<number>, count: number): { x: number[]; y: number[] } {
	const k = Math.max(0, Math.min(Math.min(x.length, y.length), Math.floor(count)));
	return { x: Array.from({ length: k }, (_, i) => x[i]), y: Array.from({ length: k }, (_, i) => y[i]) };
}
