// 단계별 그림: 전부 WASM export를 불러 계산한다 (JS로 다시 짠 수치 코드 없음).
import { readVector } from '$lib/gridtopinn';
import type { Step } from '$lib/gridtopinn';
import { drawPlot, type Series } from './plot';

/** 함수 반환값의 화면 표시 단위 (목록 파일에서 읽는다). 계산은 SI, 표시만 바꾼다. */
function displayOf(step: Step, fn: string) {
	return step.manifest.functions.find((f) => f.name === fn)?.display ?? { unit: 'm/s', scale: 1 };
}

/** 1단계: 도함수 방법 4가지의 Newton 반복 오차 (로그 눈금). 정답은 Froll = 0일 때의 해석해. */
export function demoStep1(step: Step, canvas: HTMLCanvasElement): string {
	const P = 600e3, rho = 1.225, Cd = 0.9, A = 1.5, v0 = 50, h = 1e-4;
	const exact = step.fn('top_speed_analytic', 'f64')(P, rho, Cd, A) as number;
	const d = displayOf(step, 'top_speed_iterates');
	const open = step.fn('top_speed_analytic', 'f64')(P, rho, 0.8, A) as number;
	const colors = ['#1b6', '#c50', '#05c', '#a0a'];
	const names = ['손 유도', '전진차분', '중심차분', '이중수'];
	const series: Series[] = [1, 2, 3, 4].map((m, k) => {
		const it = readVector(step, step.fn('top_speed_iterates', 'f64')(P, rho, Cd, A, 0, v0, m, h), 'f64');
		const err = Array.from(it, (v) => Math.abs(v - exact) * d.scale);
		return { label: names[k], color: colors[k], x: err.map((_, i) => i), y: err };
	});
	drawPlot(canvas, series, { logY: true, xlabel: '반복 횟수', ylabel: `|v - v*| [${d.unit}]` });
	return `최고속도 닫힘 ${(exact * d.scale).toFixed(1)} ${d.unit}, 열림 ${(open * d.scale).toFixed(1)} ${d.unit}, DRS 이득 ${((open - exact) * d.scale).toFixed(1)} ${d.unit}. 반복 수: ${series.map((s) => `${s.label} ${s.x.length}`).join(', ')}`;
}

/** 2단계: DRS가 t_open에 열릴 때 v(t)와, 적응형 적분기의 걸음 크기. */
export function demoStep2(step: Step, canvas: HTMLCanvasElement): string {
	const args = [600e3, 800, 1.225, 1.5, 0, 0.9, 0.8, 20, 80] as const; // P m ρ A Froll Cd_closed Cd_open t_open t_end
	const d = displayOf(step, 'trajectory_y');
	const run = (method: number) => {
		const tr = step.fn('drs_run', 'f64')(method, 0.5, 1e-6, ...args);
		return {
			t: readVector(step, step.fn('trajectory_t', 'f64')(tr), 'f64'),
			y: readVector(step, step.fn('trajectory_y', 'f64')(tr), 'f64').map((v) => v * d.scale)
		};
	};
	const euler = run(1), rk4 = run(2), ada = run(3);
	drawPlot(
		canvas,
		[
			{ label: 'Euler', color: '#c50', x: euler.t, y: euler.y },
			{ label: 'RK4', color: '#05c', x: rk4.t, y: rk4.y },
			{ label: '적응형 (점 = 걸음)', color: '#1b6', x: ada.t, y: ada.y, dots: true }
		],
		{ xlabel: 't [s]', ylabel: `v [${d.unit}]` }
	);
	const dt = Array.from(ada.t.slice(1), (t, i) => t - ada.t[i]);
	const near = dt.filter((_, i) => ada.t[i] >= 19 && ada.t[i] <= 25);
	return `적응형 걸음 ${dt.length}개, 최대 Δt ${Math.max(...dt).toFixed(2)} s, t_open=20 s 부근 최소 Δt ${Math.min(...near).toFixed(3)} s`;
}
