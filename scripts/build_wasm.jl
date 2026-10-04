# build_wasm.jl — Julia 커널을 WASM으로 컴파일하는 스크립트
#
# 계획:
# - WasmTarget.jl을 사용해 src/StepN/*.jl을 WasmGC WASM으로 컴파일
# - 산출물(.wasm)과 조작 항목 목록 파일( JSON)을 web/public/에 배치
#
# 현재까지 미확정 사항 (1단계 검증에서 확인):
# - WasmTarget.jl 지원 Julia 버전 (1.12/1.13 필요 예상 → Julia 업그레이드 필요 여부)
# - JS에서 WasmGC 배열을 읽는 방법
# - 컴파일 가능한 코드 범위 (타입 추론 완전성, 동적 디스패치 금지)
#
# 사용법 (가상):
#   julia --project=. scripts/build_wasm.jl --step 1 --out web/public/

println("WASM 빌드 스크립트 자리 — 1단계 검증 후 구현")
