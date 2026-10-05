// 아주 작은 canvas 선 그래프. 배경은 흰색, 눈금은 시작/끝 값만 표시한다.
export interface Series {
	label: string;
	color: string;
	x: ArrayLike<number>;
	y: ArrayLike<number>;
	/** 선 대신 점으로 그림 */
	dots?: boolean;
}
export interface PlotOpts {
	logY?: boolean;
	xlabel?: string;
	ylabel?: string;
}

const PAD = { l: 56, r: 12, t: 14, b: 34 };

export function drawPlot(canvas: HTMLCanvasElement, series: Series[], o: PlotOpts = {}) {
	const ctx = canvas.getContext('2d');
	if (!ctx) throw new Error('canvas 2d 컨텍스트를 얻지 못했다');
	const { width: W, height: H } = canvas;
	ctx.fillStyle = '#fff';
	ctx.fillRect(0, 0, W, H);

	const ty = (v: number) => (o.logY ? Math.log10(Math.max(v, 1e-18)) : v);
	let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
	for (const s of series)
		for (let i = 0; i < s.x.length; i++) {
			const y = ty(s.y[i]);
			if (!Number.isFinite(s.x[i]) || !Number.isFinite(y)) continue;
			x0 = Math.min(x0, s.x[i]); x1 = Math.max(x1, s.x[i]);
			y0 = Math.min(y0, y); y1 = Math.max(y1, y);
		}
	if (!(x1 > x0)) { x0 -= 1; x1 += 1; }
	if (!(y1 > y0)) { y0 -= 1; y1 += 1; }
	const px = (x: number) => PAD.l + ((x - x0) / (x1 - x0)) * (W - PAD.l - PAD.r);
	const py = (y: number) => H - PAD.b - ((y - y0) / (y1 - y0)) * (H - PAD.t - PAD.b);

	ctx.strokeStyle = '#888';
	ctx.strokeRect(PAD.l, PAD.t, W - PAD.l - PAD.r, H - PAD.t - PAD.b);
	ctx.fillStyle = '#333';
	ctx.font = '11px sans-serif';
	const fmt = (v: number) => (o.logY ? `1e${v.toFixed(0)}` : Math.abs(v) >= 1000 || (v !== 0 && Math.abs(v) < 0.01) ? v.toExponential(1) : v.toPrecision(4));
	ctx.fillText(fmt(y1), 4, PAD.t + 10);
	ctx.fillText(fmt(y0), 4, H - PAD.b);
	ctx.fillText(fmt(x0), PAD.l, H - PAD.b + 14);
	ctx.fillText(fmt(x1), W - PAD.r - 30, H - PAD.b + 14);
	if (o.xlabel) ctx.fillText(o.xlabel, (W - PAD.l) / 2, H - 4);
	if (o.ylabel) ctx.fillText(o.ylabel, 4, PAD.t + 24);

	series.forEach((s, k) => {
		ctx.strokeStyle = ctx.fillStyle = s.color;
		ctx.beginPath();
		let pen = false;
		for (let i = 0; i < s.x.length; i++) {
			const y = ty(s.y[i]);
			if (!Number.isFinite(s.x[i]) || !Number.isFinite(y)) { pen = false; continue; }
			const X = px(s.x[i]), Y = py(y);
			if (s.dots) ctx.fillRect(X - 2, Y - 2, 4, 4);
			else if (pen) ctx.lineTo(X, Y);
			else ctx.moveTo(X, Y);
			pen = true;
		}
		if (!s.dots) ctx.stroke();
		ctx.fillText(s.label, W - PAD.r - 130, PAD.t + 12 + 13 * k);
	});
}
