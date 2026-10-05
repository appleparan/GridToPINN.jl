export type SeriesRole = 'primary' | 'reference' | 'muted';
export interface PlotSeries {
	label: string;
	role: SeriesRole;
	x: ArrayLike<number>;
	y: ArrayLike<number>;
	points?: boolean;
	dashed?: boolean;
}
/** A vertical dashed line at x. */
export interface PlotMarker {
	x: number;
	label: string;
}
