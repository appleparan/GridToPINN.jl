// Worker의 메시지 처리 로직. 브라우저 전역에 의존하지 않아 Node에서 시험할 수 있다.
import { readVector } from './arrays';
import type { Arg, CallSpec, Handle, Request, Response, TypedVec, Value } from './protocol';
import type { Precision, Step } from './types';

export interface WorkerState {
	step: Step | null;
	handles: Map<number, unknown>;
	next: number;
	cancelled: Set<number>;
}
export const newState = (): WorkerState => ({ step: null, handles: new Map(), next: 1, cancelled: new Set() });

const need = (s: WorkerState): Step => {
	if (!s.step) throw new Error('먼저 load를 호출해야 한다');
	return s.step;
};

function resolve(s: WorkerState, a: Arg): unknown {
	if (typeof a === 'number') return a;
	if (!s.handles.has(a.handle)) throw new Error(`알 수 없는 핸들 ${a.handle} (이미 release됐는가?)`);
	return s.handles.get(a.handle);
}

/** 숫자는 그대로, 그 밖(GC 참조)은 핸들 표에 넣는다. */
function toValue(s: WorkerState, r: unknown): Value {
	if (typeof r === 'number') return r;
	const handle = s.next++;
	s.handles.set(handle, r);
	return { handle };
}

const callRaw = (s: WorkerState, p: Precision, c: CallSpec) => need(s).fn(c.fn, p)(...c.args.map((a) => resolve(s, a)));

function readSpec(s: WorkerState, p: Precision, v: Handle | CallSpec): TypedVec {
	const ref = 'handle' in v ? resolve(s, v) : callRaw(s, p, v);
	return readVector(need(s), ref, p);
}

/** load 외의 동기 요청 하나를 처리한다. 실패는 error 응답으로 돌려준다(예외를 던지지 않음). */
export function handleMessage(s: WorkerState, msg: Request): Response {
	try {
		switch (msg.op) {
			case 'call':
				return { id: msg.id, type: 'ok', result: toValue(s, callRaw(s, msg.precision, msg)) };
			case 'read':
				return { id: msg.id, type: 'ok', result: readSpec(s, msg.precision, { handle: msg.handle }) };
			case 'release':
				for (const h of msg.handles) s.handles.delete(h);
				return { id: msg.id, type: 'ok' };
			case 'stop':
				s.cancelled.add(msg.target);
				return { id: msg.id, type: 'ok' };
			default:
				throw new Error(`처리할 수 없는 op: ${(msg as { op: string }).op}`);
		}
	} catch (e) {
		return { id: msg.id, type: 'error', message: e instanceof Error ? e.message : String(e) };
	}
}

/** run 요청의 프레임 하나를 계산한다. */
export function runFrame(s: WorkerState, msg: Extract<Request, { op: 'run' }>, frame: number): Response {
	try {
		const result = toValue(s, callRaw(s, msg.precision, msg));
		const vectors = (msg.vectors ?? []).map((v) => readSpec(s, msg.precision, v));
		const scalars = (msg.scalars ?? []).map((c) => callRaw(s, msg.precision, c) as number);
		// 프레임마다 생기는 결과 핸들(참조)은 쌓이지 않게 바로 푼다
		if (typeof result !== 'number') s.handles.delete(result.handle);
		return { id: msg.id, type: 'frame', frame, result, vectors, scalars };
	} catch (e) {
		return { id: msg.id, type: 'error', message: e instanceof Error ? e.message : String(e) };
	}
}

export const transferables = (r: Response): ArrayBuffer[] => {
	const bufs: ArrayBuffer[] = [];
	if (r.type === 'frame') for (const v of r.vectors) bufs.push(v.buffer as ArrayBuffer);
	else if (r.type === 'ok' && ArrayBuffer.isView(r.result)) bufs.push(r.result.buffer as ArrayBuffer);
	return bufs;
};
