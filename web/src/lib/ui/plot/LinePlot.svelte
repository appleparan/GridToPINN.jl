<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import type uPlotType from 'uplot';
	import type { PlotMarker, PlotSeries, SeriesRole } from './types';

	let {
		series,
		xLabel,
		yLabel,
		logY = false,
		markers = [],
		height = 320
	}: {
		series: PlotSeries[];
		xLabel: string;
		yLabel: string;
		logY?: boolean;
		markers?: PlotMarker[];
		height?: number;
	} = $props();

	const LOG_FLOOR = 1e-17;
	const ROLE_VAR: Record<SeriesRole, string> = {
		primary: '--plot-primary',
		reference: '--plot-reference',
		muted: '--plot-muted'
	};

	let root: HTMLDivElement | undefined = $state();
	let UPlot: typeof uPlotType | undefined = $state();
	let plot: uPlotType | undefined;
	let builtKey = '';
	// Bumped when <html> toggles its theme class. mode.current can change before the class lands,
	// which would make us read the old theme's --plot-* values.
	let themeTick = $state(0);

	const pointCount = $derived.by(() => {
		const s = series.find((q) => q.role === 'primary');
		if (!s) return 0;
		let n = 0;
		for (let i = 0; i < s.y.length; i++) if (Number.isFinite(s.y[i])) n++;
		return n;
	});

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
	function buildData(U: typeof uPlotType): uPlotType.AlignedData {
		const tables = series.map((s) => {
			const x = Array.from(s.x);
			const y = Array.from(s.y, clean);
			return [x, y] as uPlotType.AlignedData;
		});
		return U.join(tables);
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
			scales: { x: { time: false }, y: logY ? { distr: 3 } : {} },
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
						points: s.points
							? { show: true, size: s.role === 'primary' ? 7 : 5, fill: color, stroke: color }
							: { show: false }
					};
				})
			],
			cursor: { drag: { x: false, y: false } },
			legend: { show: false },
			hooks: {
				draw: [
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
							ctx.fillText(m.label, cx + 4 * dpr, u.bbox.top + 12 * dpr);
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
		const key = [theme, logY, xLabel, yLabel, height, ...series.map((s) => `${s.label}|${s.role}|${s.points}|${s.dashed}`)].join(
			'\n'
		);
		const data = buildData(U);
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
			{#each series as s (s.label)}
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
	{/if}
</div>

<style>
	.lineplot :global(.u-select) {
		background: transparent;
	}
</style>
