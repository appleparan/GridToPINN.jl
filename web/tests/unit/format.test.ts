import { expect, test } from 'vitest';
import { formatValue } from '../../src/lib/ui/format';

test.each([
	[0, '0'], [1.5, '1.5'], [323.4567, '323.5'], [100, '100'], [0.01234, '0.01234'],
	[1e-6, '1.00e-6'], [2.5e7, '2.50e+7'], [-0.5, '-0.5'],
	[NaN, 'NaN'], [Infinity, '∞'], [-Infinity, '-∞']
])('formatValue(%s) = %s', (v, s) => expect(formatValue(v)).toBe(s));
