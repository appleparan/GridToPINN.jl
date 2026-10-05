// Worker 진입점. 번들러가 `new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' })`로 불러온다.
// index.ts는 이 파일을 가져오지 않는다 (사전 렌더링 중 전역 `self` 접근을 피하려고).
import { handleMessage, newState, runFrame, transferables } from './handler';
import { loadStep } from './loader';
import type { Request, Response } from './protocol';

declare const self: { postMessage(m: unknown, t?: Transferable[]): void; onmessage: ((e: { data: Request }) => void) | null };

const state = newState();
const post = (r: Response) => self.postMessage(r, transferables(r));
const tick = () => new Promise<void>((r) => setTimeout(r, 0));

async function run(msg: Extract<Request, { op: 'run' }>) {
	let frame = 0;
	for (; frame < msg.frames; frame++) {
		await tick(); // 이벤트 루프를 한 번 돌려 stop 메시지가 끼어들 수 있게 한다
		if (state.cancelled.has(msg.id)) break;
		const r = runFrame(state, msg, frame + 1);
		post(r);
		if (r.type === 'error') return;
	}
	const stopped = frame < msg.frames;
	state.cancelled.delete(msg.id);
	post({ id: msg.id, type: 'ok', result: { frames: frame, stopped } });
}

self.onmessage = (e) => {
	const msg = e.data;
	if (msg.op === 'load') {
		loadStep(msg.baseUrl, msg.step).then(
			(step) => {
				state.step = step;
				state.handles.clear();
				post({ id: msg.id, type: 'ok', result: { manifest: step.manifest } });
			},
			(err) => post({ id: msg.id, type: 'error', message: err instanceof Error ? err.message : String(err) })
		);
	} else if (msg.op === 'run') {
		run(msg).catch((err) => post({ id: msg.id, type: 'error', message: String(err) }));
	} else {
		post(handleMessage(state, msg));
	}
};
