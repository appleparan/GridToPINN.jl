// Worker 위의 Promise API. Worker는 호출하는 쪽이 만들어 넘긴다(번들러에 의존하지 않음).
import type { Arg, CallSpec, Handle, Request, Response, TypedVec, Value } from './protocol';
import type { Manifest, Precision } from './types';

export interface WorkerLike {
	postMessage(m: unknown): void;
	addEventListener(type: 'message', l: (e: { data: Response }) => void): void;
	addEventListener(type: 'error', l: (e: { message?: string }) => void): void;
}

export interface Frame {
	frame: number;
	result: Value;
	vectors: TypedVec[];
	scalars: number[];
}
export interface RunOptions {
	fn: string;
	precision: Precision;
	args: Arg[];
	frames: number;
	vectors?: (Handle | CallSpec)[];
	scalars?: CallSpec[];
	onFrame?: (f: Frame) => void;
}

type Body = Request extends infer R ? (R extends unknown ? Omit<R, 'id'> : never) : never;

export function createClient(worker: WorkerLike) {
	let nextId = 1;
	const pending = new Map<number, { resolve: (r: any) => void; reject: (e: Error) => void; onFrame?: (f: Frame) => void }>();

	worker.addEventListener('message', (e) => {
		const r = e.data;
		const p = pending.get(r.id);
		if (!p) return;
		if (r.type === 'frame') p.onFrame?.(r);
		else {
			pending.delete(r.id);
			if (r.type === 'error') p.reject(new Error(r.message));
			else p.resolve(r.result);
		}
	});
	worker.addEventListener('error', (e) => {
		const err = new Error(`Worker 오류: ${e.message ?? '알 수 없음'}`);
		for (const p of pending.values()) p.reject(err);
		pending.clear();
	});

	function send<T>(msg: Body, onFrame?: (f: Frame) => void): { id: number; promise: Promise<T> } {
		const id = nextId++;
		const promise = new Promise<T>((resolve, reject) => pending.set(id, { resolve, reject, onFrame }));
		worker.postMessage({ ...msg, id });
		return { id, promise };
	}

	return {
		load: (baseUrl: string, step: number) => send<{ manifest: Manifest }>({ op: 'load', baseUrl, step }).promise,
		call: (fn: string, precision: Precision, args: Arg[]) => send<Value>({ op: 'call', fn, precision, args }).promise,
		read: (handle: Handle, precision: Precision) => send<TypedVec>({ op: 'read', handle: handle.handle, precision }).promise,
		release: (handles: Handle[]) => send<void>({ op: 'release', handles: handles.map((h) => h.handle) }).promise,
		/** 반복 호출. done은 모든 프레임 뒤(또는 stop 뒤)에 풀리고, 오류는 reject된다. */
		run(o: RunOptions) {
			const { onFrame, ...rest } = o;
			const { id, promise } = send<{ frames: number; stopped: boolean }>({ op: 'run', ...rest }, onFrame);
			return { done: promise, stop: () => send<void>({ op: 'stop', target: id }).promise };
		}
	};
}
export type Client = ReturnType<typeof createClient>;
