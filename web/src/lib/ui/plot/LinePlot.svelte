<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import type uPlotType from 'uplot';
	import { formatValue } from '../format';
	import { decimate } from './decimate';
	import type { PlotMarker, PlotSeries, SeriesRole } from './types';

	let {
		series,
		xLabel,
		yLabel,
		logY = false,
		markers = [],
		yRange,
		height = 320
	}: {
		series: PlotSeries[];
		xLabel: string;
		yLabel: string;
		logY?: boolean;
		markers?: PlotMarker[];
		/** Fixed y window; series outside it are clipped. Default: fit to all series. */
		yRange?: { min: number; max: number };
		height?: number;
	} = $props();

	const LOG_FLOOR = 1e-17;
	const ROLE_VAR: Record<SeriesRole, string> = {
		primary: '--plot-primary',
		reference: '--plot-reference',
		muted: '--plot-muted',
		ghost: '--plot-ghost'
	};

	let root: HTMLDivElement | undefined = $state();
	let UPlot: typeof uPlotType | undefined = $state();
	let plot: uPlotType | undefined;
	let builtKey = '';
	// Bumped when <html> toggles its theme class. mode.current can change before the class lands,
	// which would make us read the old theme's --plot-* values.
	let themeTick = $state(0);

	// Per-array caches: playback swaps `series` every frame but the static curves keep their array identity,
	// so neither the finite-point count nor the cleaned [x, y] table is recomputed for them.
	const counts = new WeakMap<ArrayLike<number>, number>();
	function finiteCount(y: ArrayLike<number>): number {
		let n = counts.get(y);
		if (n === undefined) {
			n = 0;
			for (let i = 0; i < y.length; i++) if (Number.isFinite(y[i])) n++;
			counts.set(y, n);
		}
		return n;
	}
	const tables = new WeakMap<ArrayLike<number>, { x: ArrayLike<number>; logY: boolean; cap: number; table: uPlotType.AlignedData }>();

	const pointCount = $derived.by(() => {
		// the ghost, when present, is the full selected series: playback must not change this count
		const s = series.find((q) => q.role === 'ghost') ?? series.find((q) => q.role === 'primary');
		if (!s) return 0;
		return finiteCount(s.y);
	});

	// Hover readout: the sample under the cursor (of the drawn, possibly thinned data), per visible curve.
	// Plain state outside the build effect, so moving the mouse never rebuilds the uPlot instance.
	type CursorRow = { label: string; role: SeriesRole; y: string };
	let cursor = $state.raw<{ x: string; rows: CursorRow[] } | undefined>();
	const splitLabel = (l: string) => ({
		name: l.replace(/\s*\[[^\]]*\]\s*$/, ''),
		unit: /\[([^\]]*)\]\s*$/.exec(l)?.[1] ?? ''
	});
	const NEAREST_SCAN = 50; // joined tables hold nulls where only another series has a sample

	function readCursor(u: uPlotType) {
		const idx = u.cursor.idx;
		const xs = u.data[0];
		if (idx == null || idx < 0 || idx >= xs.length) {
			cursor = undefined;
			return;
		}
		const x = xs[idx] as number;
		const span = (xs[xs.length - 1] as number) - (xs[0] as number);
		const rows: CursorRow[] = [];
		series.forEach((s, i) => {
			if (s.role === 'muted' || s.role === 'ghost') return;
			const ys = u.data[i + 1];
			let best: number | undefined;
			if (s.role === 'reference' && s.x.length <= 2) {
				// a two-point constant line has samples at its ends only; any of them is its value
				const k = ys.findIndex((v) => v != null);
				rows.push({ label: s.label, role: s.role, y: k < 0 ? '–' : formatValue(ys[k] as number) });
				return;
			}
			for (let d = 0; d <= NEAREST_SCAN && best === undefined; d++) {
				for (const k of d === 0 ? [idx] : [idx - d, idx + d]) {
					if (k < 0 || k >= ys.length || ys[k] == null) continue;
					if (Math.abs((xs[k] as number) - x) > 0.03 * span) continue;
					best = k;
					break;
				}
			}
			rows.push({ label: s.label, role: s.role, y: best === undefined ? '–' : formatValue(ys[best] as number) });
		});
		const text = formatValue(x);
		const prev = cursor;
		if (prev && prev.x === text && prev.rows.length === rows.length && prev.rows.every((r, i) => r.y === rows[i].y && r.label === rows[i].label)) return;
		cursor = { x: text, rows };
	}

	// Legend follows `order` (default: series order), so the draw order can differ from it.
	const legendSeries = $derived(
		series.filter((q) => q.role !== 'ghost').sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
	);

	onMount(() => {
		let disposed = false;
		(async () => {
			const [mod] = await Promise.all([import('uplot'), import('uplot/dist/uPlot.min.css')]);
			if (!disposed) UPlot = mod.default;
		})();
		const mo = new MutationObserver(() => themeTick++);
		mo.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
		return () => {
			mo.disconnect();
			disposed = true;
			plot?.destroy();
			plot = undefined;
		};
	});

	function cssVar(name: string): string {
		return root ? getComputedStyle(root).getPropertyValue(name).trim() : '';
	}

	function clean(v: number): number | null {
		if (!Number.isFinite(v)) return null;
		return logY && v <= 0 ? LOG_FLOOR : v;
	}

	// One [x, y] table per series; uPlot.join aligns series that sit on different x grids.
	function buildData(U: typeof uPlotType, cap: number): uPlotType.AlignedData {
		const aligned = series.map((s) => {
			const hit = tables.get(s.y);
			if (hit && hit.x === s.x && hit.logY === logY && hit.cap === cap) return hit.table;
			// display only: a series longer than ~4 points per pixel is thinned (min/max kept) before drawing
			const d = decimate(s.x, s.y, cap);
			const table = [d.x, d.y.map(clean)] as uPlotType.AlignedData;
			tables.set(s.y, { x: s.x, logY, cap, table });
			return table;
		});
		return U.join(aligned);
	}

	// Log axis: label powers of ten only, thinned to at most ~6 ticks.
	function decadeSplits(_u: uPlotType, _axis: number, min: number, max: number): number[] {
		const lo = Math.ceil(Math.log10(min));
		const hi = Math.floor(Math.log10(max));
		const stride = Math.max(1, Math.ceil((hi - lo + 1) / 6));
		const out: number[] = [];
		for (let e = lo; e <= hi; e += stride) out.push(Number(`1e${e}`)); // not 10 ** e: 10 ** -17 is 1.0000000000000001e-17
		return out;
	}
	function decadeLabel(v: number): string {
		const e = Math.round(Math.log10(v));
		return e >= -2 && e <= 3 ? String(Number(`1e${e}`)) : `1e${e}`;
	}

	function buildOptions(U: typeof uPlotType, width: number): uPlotType.Options {
		const axis = cssVar('--plot-axis');
		const grid = cssVar('--plot-grid');
		const font = '12px "JetBrains Mono Variable", ui-monospace, monospace';
		const labelFont = '12px "Pretendard Variable", Pretendard, system-ui, sans-serif';
		const axisBase = {
			stroke: axis,
			font,
			labelFont,
			grid: { stroke: grid, width: 1 },
			ticks: { stroke: grid, width: 1 }
		};
		return {
			width,
			height,
			scales: {
				x: { time: false },
				y: logY
					? { distr: 3 }
					: {
							range: (_u: uPlotType, lo: number | null, hi: number | null): uPlotType.Range.MinMax => {
								if (yRange) return [yRange.min, yRange.max];
								if (lo == null || hi == null) return [null, null];
								return U.rangeNum(lo, hi, 0.1, true);
							}
						}
			},
			axes: [
				{ ...axisBase, label: xLabel, labelSize: 22 },
				{
					...axisBase,
					label: yLabel,
					labelSize: 22,
					size: 64,
					...(logY ? { splits: decadeSplits, filter: (_u: uPlotType, s: number[]) => s, values: (_u: uPlotType, v: number[]) => v.map(decadeLabel) } : {})
				}
			],
			series: [
				{},
				...series.map((s) => {
					const color = cssVar(ROLE_VAR[s.role]);
					return {
						label: s.label,
						stroke: color,
						width: s.role === 'primary' ? 2.25 : 1.5,
						dash: s.dashed ? [6, 4] : undefined,
						spanGaps: true,
						points: s.points && s.role !== 'ghost'
							? { show: true, size: s.role === 'primary' ? 7 : 5, fill: color, stroke: color }
							: { show: false }
					};
				})
			],
			cursor: { drag: { x: false, y: false } },
			legend: { show: false },
			hooks: {
				setCursor: [readCursor],
				draw: [
					(u: uPlotType) => {
						// playback head: a filled dot at the last finite point of the series that asks for it
						const ctx = u.ctx;
						series.forEach((s, i) => {
							if (!s.head) return;
							const ys = u.data[i + 1];
							const xs = u.data[0];
							let k = ys.length - 1;
							while (k >= 0 && ys[k] == null) k--;
							if (k < 0) return;
							const cx = u.valToPos(xs[k], 'x', true);
							const cy = u.valToPos(ys[k] as number, 'y', true);
							const r = 6 * devicePixelRatio;
							ctx.save();
							ctx.beginPath();
							ctx.arc(cx, cy, r, 0, 2 * Math.PI);
							ctx.fillStyle = cssVar(ROLE_VAR[s.role]);
							ctx.fill();
							ctx.lineWidth = 2 * devicePixelRatio;
							ctx.strokeStyle = cssVar('--card');
							ctx.stroke();
							ctx.restore();
						});
					},
					(u: uPlotType) => {
						const ctx = u.ctx;
						const dpr = devicePixelRatio;
						ctx.save();
						ctx.strokeStyle = cssVar('--plot-axis');
						ctx.fillStyle = cssVar('--plot-axis');
						ctx.lineWidth = dpr;
						ctx.setLineDash([4 * dpr, 4 * dpr]);
						ctx.font = `${11 * dpr}px "Pretendard Variable", Pretendard, system-ui, sans-serif`;
						for (const m of markers) {
							const cx = u.valToPos(m.x, 'x', true);
							if (cx < u.bbox.left || cx > u.bbox.left + u.bbox.width) continue;
							ctx.beginPath();
							ctx.moveTo(cx, u.bbox.top);
							ctx.lineTo(cx, u.bbox.top + u.bbox.height);
							ctx.stroke();
							// Bottom of the plot area: curves and reference lines usually run along the top.
							const w = ctx.measureText(m.label).width;
							const flip = cx + 4 * dpr + w > u.bbox.left + u.bbox.width;
							ctx.setLineDash([]);
							ctx.textAlign = flip ? 'right' : 'left';
							ctx.textBaseline = 'bottom';
							const tx = cx + (flip ? -4 : 4) * dpr;
							const ty = u.bbox.top + u.bbox.height - 6 * dpr;
							// Plate in the card color so the label stays readable over curves and axis lines.
							ctx.fillStyle = cssVar('--card');
							ctx.fillRect(flip ? tx - w - 2 * dpr : tx - 2 * dpr, ty - 14 * dpr, w + 4 * dpr, 16 * dpr);
							ctx.fillStyle = cssVar('--plot-axis');
							ctx.fillText(m.label, tx, ty);
							ctx.setLineDash([4 * dpr, 4 * dpr]);
						}
						ctx.restore();
					}
				]
			}
		};
	}

	// Rebuild the uPlot instance only when its shape changes; otherwise just swap the data.
	$effect(() => {
		const U = UPlot;
		const el = root;
		if (!U || !el) return;
		if (series.length === 0) {
			// nothing to draw (e.g. the first compute failed): keep the root mounted, drop any stale chart
			untrack(() => {
				plot?.destroy();
				plot = undefined;
				builtKey = '';
			});
			return;
		}
		const theme = themeTick;
		const key = [theme, logY, xLabel, yLabel, height, ...series.map((s) => `${s.label}|${s.role}|${s.points}|${s.dashed}|${s.head}`)].join(
			'\n'
		);
		const data = buildData(U, Math.max(1000, 4 * (el.clientWidth || 600)));
		void markers.length;
		untrack(() => {
			if (plot && key === builtKey) {
				plot.setData(data);
				plot.redraw();
				return;
			}
			plot?.destroy();
			plot = new U(buildOptions(U, el.clientWidth || 600), data, el);
			builtKey = key;
		});
	});

	$effect(() => {
		const el = root;
		if (!el) return;
		const ro = new ResizeObserver(() => {
			const w = el.clientWidth;
			if (plot && w > 0) plot.setSize({ width: w, height });
		});
		ro.observe(el);
		return () => ro.disconnect();
	});
</script>

<div class="lineplot w-full" data-testid="plot" data-points={pointCount}>
	<div bind:this={root} class="w-full"></div>
	{#if series.length > 0}
		<ul class="text-muted-foreground mt-3 flex flex-wrap gap-x-4 gap-y-1.5 text-xs" aria-label="범례">
			{#each legendSeries as s (s.label)}
				<li class="flex items-center gap-1.5" class:text-foreground={s.role === 'primary'} class:font-medium={s.role === 'primary'}>
					<svg width="18" height="8" aria-hidden="true">
						<line
							x1="1" y1="4" x2="17" y2="4"
							stroke="var({ROLE_VAR[s.role]})"
							stroke-width={s.role === 'primary' ? 2.5 : 1.75}
							stroke-dasharray={s.dashed ? '4 3' : undefined}
							stroke-linecap="round"
						/>
					</svg>
					{s.label}
				</li>
			{/each}
		</ul>
		<div
			class="num text-muted-foreground mt-1.5 flex min-h-5 flex-wrap gap-x-4 gap-y-0.5 text-xs"
			class:invisible={!cursor}
			data-testid="plot-cursor"
			aria-hidden="true"
		>
			{#if cursor}
				<span>{splitLabel(xLabel).name} = <span class="text-foreground">{cursor.x}</span> {splitLabel(xLabel).unit}</span>
				{#each cursor.rows as r (r.label)}
					<span>{r.label} <span class="text-foreground">{r.y}</span> {splitLabel(yLabel).unit}</span>
				{/each}
			{:else}
				&nbsp;
			{/if}
		</div>
	{/if}
</div>

<style>
	.lineplot :global(.u-select) {
		background: transparent;
	}
</style>
