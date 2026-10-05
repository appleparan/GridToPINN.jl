import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FetchFn } from '../../src/lib/gridtopinn';

export const WASM_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../static/wasm');
export const BASE_URL = 'http://test/wasm';

/** 실제 산출물(static/wasm)을 디스크에서 읽는 fetch. */
export const fileFetch: FetchFn = async (url) => {
	const file = path.join(WASM_DIR, url.replace(BASE_URL + '/', ''));
	if (!fs.existsSync(file)) return { ok: false, status: 404, json: async () => ({}), arrayBuffer: async () => new ArrayBuffer(0) };
	const buf = fs.readFileSync(file);
	return {
		ok: true, status: 200,
		json: async () => JSON.parse(buf.toString('utf8')),
		arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer
	};
};
