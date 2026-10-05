export type SeriesRole = 'primary' | 'reference' | 'muted' | 'ghost';
export interface PlotSeries {
	label: string;
	role: SeriesRole;
	x: ArrayLike<number>;
	y: ArrayLike<number>;
	points?: boolean;
	dashed?: boolean;
	/** Draw a filled dot at the last finite point (the moving head during playback). */
	head?: boolean;
	/** Legend position; default keeps the series order. Draw order is the series order. */
	order?: number;
}
/** A vertical dashed line at x. */
export interface PlotMarker {
	x: number;
	label: string;
}
