import { loadWasm } from "$lib/wasm";

export const prerender = true;

export default async function testPage() {
  // WASM 로딩 시험 페이지
  // 각 단계의 WASM을 불러 실행하고 숫자·간단 그림으로 결과를 확인.
  // "브라우저에서 실제로 돈다"를 증명하는 용도.
  //
  // TODO: 1단계 WASM 컴파일 결과물이 나오면 실제 호출 코드 작성.
  // 현재는 WASM 로딩이 미구현이므로 안내만 표시.

  return {
    data: {
      status: "not-built",
      note: "WASM 컴파일 전입니다. 1단계 검증 후 이 페이지를 업데이트하세요.",
    },
  };
}

export function load({ data }: { data: { status: string; note: string } }) {
  return data;
}
