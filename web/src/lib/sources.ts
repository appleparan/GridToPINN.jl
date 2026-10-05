// 화면에 보이는 코드 = 컴파일된 코드: 커널 .jl 파일을 ?raw로 그대로 불러온다 (표시용 사본 없음).
import type { SourceRange } from './gridtopinn/types';

const files = import.meta.glob('../../../src/**/*.jl', { query: '?raw', import: 'default', eager: true }) as Record<string, string>;

// '../../../src/step1/drs.jl' -> 'src/step1/drs.jl'
const byPath = new Map(Object.entries(files).map(([k, v]) => [k.replace(/^(\.\.\/)+/, ''), v]));

/** 매니페스트의 {file, lines:[시작, 끝]} 범위의 소스 텍스트. */
export function sourceText({ file, lines }: SourceRange): string {
	const text = byPath.get(file);
	if (text === undefined) throw new Error(`소스 파일 '${file}'을 찾지 못했다`);
	return text.split('\n').slice(lines[0] - 1, lines[1]).join('\n');
}
