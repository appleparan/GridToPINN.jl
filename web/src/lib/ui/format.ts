/** Format a number for readouts: 4 significant digits in a readable range (1e-3 to 1e7), exponent form outside it. */
export function formatValue(v: number): string {
	if (Number.isNaN(v)) return 'NaN';
	if (v === Infinity) return '∞';
	if (v === -Infinity) return '-∞';
	if (v === 0) return '0';
	const a = Math.abs(v);
	if (a >= 1e-3 && a < 1e7) return String(Number(v.toPrecision(4)));
	return v.toExponential(2);
}
