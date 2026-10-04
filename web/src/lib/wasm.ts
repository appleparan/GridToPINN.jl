// WASM 모듈 초기화 헬퍼
// Julia WASM 모듈을 불러오고, 배열 전달·호출 규약을 캡슐화한다.
//
// 제약:
// - 브라우저 환경 전용. SSR/사전 렌더링 시 불러오기만 해도 오류 나지 않게 작성.
// - WASM 파일 경로는 인자로 받아 사이트 기준 경로 변경에 대응.
// - WasmTarget.jl 출력과의 연동 방식은 1단계 검증에서 확정.

export interface WasmModule {
  // 단계별 함수 호출 인터페이스 (추후 단계 추가 시 확장)
  // 현재는 Step1의 함수들을 어떤 형태로 노출할지 검증 후 결정
  ready: boolean;
  loadError: string | null;
}

/**
 * WASM 파일을 로딩하고 초기화된 모듈을 반환한다.
 * @param wasmPath WASM 파일 경로 (사이트 기준 경로 변경 대응용 인자)
 * @returns WasmModule 또는 로딩 중 에러
 */
export async function loadWasm(wasmPath: string): Promise<WasmModule> {
  // TODO: WasmTarget.jl 출력 형식에 맞춰 실제 로딩 로직 구현
  // 현재는 자리만 확보. 1단계 검증 후 구체화.
  throw new Error("WASM 로딩 미구현 — 1단계 검증 후 구현");
}
