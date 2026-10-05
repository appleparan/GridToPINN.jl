# GridToPINN.jl

CFD를 밑바닥부터 짜서 PINN까지 가는 튜토리얼 "From Grid to PINN"의 계산 부분입니다.
Julia 커널을 WebAssembly로 컴파일해 브라우저에서 실행합니다. 서버는 없습니다.

약속은 하나입니다. 화면에 보이는 Julia 코드가 곧 브라우저에서 도는 코드입니다.
커널을 JS로 다시 짜지 않고, WASM 진입점에도 수치 코드를 넣지 않습니다.

## 현재 상태

1~3단계가 네이티브 테스트, WASM 빌드, 브라우저 검증까지 끝났습니다. 4~9단계는 아직 없습니다.

| # | 단계 | 질문 | 상태 |
|---|---|---|---|
| 1 | 미분과 Newton법 | DRS를 열면 최고속도가 얼마나 오르나 | 완료 |
| 2 | 시간 전진 | 그 속도에 도달하는 데 얼마나 걸리나 | 완료 |
| 3 | 확산 | 벽이 움직이면 물과 꿀 중 어느 쪽이 더 깊이 끌려오나 | 완료 |
| 4 | 대류 | 옮기기만 하는데 왜 모양이 망가지나 | 예정 |
| 5 | Poisson | 소용돌이 중심은 왜 압력이 낮은가 | 예정 |
| 6 | Staggered grid와 발산 제거 | 비압축성 유동에서 압력은 무슨 일을 하나 | 예정 |
| 7 | 조립 | 뚜껑만 미끄러지는 상자 안에서 유체는 어떻게 도나 | 예정 |
| 8 | PINN | 센서 몇 개의 값만으로 유동 전체를 맞힐 수 있나 | 예정 |
| 9 | GPU (선택) | 같은 코드를 GPU로 옮기면 언제 빨라지나 | 예정 |

단계별 요구사항과 설계 원칙은 [AGENTS.md](AGENTS.md)에 있습니다.

## 구조

저장소는 세 층으로 나뉩니다. 각 층은 아래 층만 읽습니다.

```
src/            커널. 모듈 GridToPINN 하나, 의존 패키지 없음
  step1/        dual.jl  derivatives.jl  newton.jl  drs.jl
  step2/        integrators.jl  adaptive.jl  acceleration.jl
  step3/        operator.jl  exact.jl  implicit.jl  simulation.jl
test/           네이티브 테스트 (step1.jl, step2.jl, step3.jl)
wasm/           WASM 빌드 환경 (WasmTarget.jl). 커널을 컴파일만 한다
  entries/      단계별 내보내기 선언: 함수, 조작 값, 대안 지점, 일치 검사 사례
  build.jl      모든 단계를 빌드해 web/static/wasm/ 에 쓴다
web/            SvelteKit 정적 사이트
  src/lib/gridtopinn/   프레임워크에 의존하지 않는 TS 연결 모듈과 Worker
  src/routes/verify/    검증 페이지
  static/wasm/          빌드 산출물 (커밋함. 커널을 고치면 다시 빌드해 함께 커밋)
docs/           아키텍처, 호출 규약, 변경 기록
```

자세한 설명은 [docs/architecture.md](docs/architecture.md), 화면에서 부르는 방법은
[docs/calling-convention.md](docs/calling-convention.md)에 있습니다.

## 실행

필요한 도구는 Julia 1.12 (`juliaup add 1.12`), Node.js 20 이상, bun, Chrome입니다.

네이티브 테스트:

```bash
julia +1.12 --project=. -e 'using Pkg; Pkg.test()'
```

WASM 빌드와 네이티브 일치 검사. 처음 한 번은 `Pkg.instantiate()`가 필요합니다.

```bash
julia +1.12 --project=wasm -e 'using Pkg; Pkg.instantiate()'
julia +1.12 --project=wasm wasm/build.jl
node wasm/check_parity.mjs
```

웹 검증. WASM 빌드가 먼저 끝나 있어야 합니다.

```bash
cd web
bun install
bun run check       # 타입 검사
bun run test        # 연결 모듈 단위 테스트 (Node에서 실제 .wasm 실행)
bun run test:e2e    # 사이트를 빌드해 Chrome으로 검증 페이지를 연다
bun run dev         # 개발 서버. /verify 에서 눈으로 확인
```

## 배포

`.wasm`과 목록 파일은 `web/static/wasm/`에 커밋되어 있습니다. 그래서 웹 빌드와 배포에는 Julia가 필요 없고,
`web/`을 루트로 `bun install && bun run build`만 하면 됩니다. 사이트에 올릴 것은 `web/build/` 폴더 하나이며
그 안에 `.wasm`이 들어 있습니다.

커널(`src/`)이나 선언(`wasm/entries/`)을 고쳤으면 산출물을 다시 만들어 함께 커밋합니다.

```bash
cd web
bun run build:wasm  # WASM 빌드와 네이티브 일치 검사 → web/static/wasm/ (커밋할 것)
bun run build       # 사이트 빌드 → web/build/
```

다시 빌드하는 것을 잊으면 CI의 `julia --project=wasm wasm/build.jl --check`가 실패합니다.

하위 경로에 올릴 때는 `BASE_PATH=/경로 bun run build`로 빌드합니다.
CI(`.github/workflows/ci.yml`)는 push와 PR마다 네이티브 테스트, 산출물 검사, 일치 검사, 웹 검사, e2e를 돌립니다.
`main`에 push되면 모든 검사가 통과한 뒤 빌드한 사이트를 GitHub Pages로 내보냅니다.
주소는 <https://grid-to-pinn.liam.kim>입니다. 사용자 지정 도메인은 저장소의 Pages 설정에 있습니다.

## 새 단계를 추가하는 방법

1. `src/stepN/`에 커널을 쓰고 `src/GridToPINN.jl`에 `include`와 `export`를 더합니다.
   `T<:AbstractFloat`에 대해 일반적으로 쓰고 Float64 리터럴을 쓰지 않습니다.
2. `test/stepN.jl`에 테스트를 쓰고 `test/runtests.jl`에 더합니다. 정답과의 비교, 수렴 차수,
   깨뜨리기, Float32와 Float64를 모두 넣습니다.
3. `wasm/entries/stepN.jl`에 진입점과 선언을 쓰고 `wasm/build.jl`의 `STEPS`에 한 줄을 더합니다.
   진입점은 타입을 고정하고 대안 번호를 커널 함수로 바꾸는 일만 합니다.
4. 빌드하고 `node wasm/check_parity.mjs`와 `bun run test:e2e`를 돌립니다. 연결 모듈과 검증 페이지는
   목록 파일을 읽으므로 고치지 않아도 새 단계가 나타납니다.

## 알려진 한계

- WasmGC를 지원하는 브라우저가 필요합니다. 최소 버전은 이 저장소에서 확인하지 않았습니다.
  검증에 쓴 것은 Node 26과 이 개발 환경의 Chrome입니다.
- 배열은 JS에서 값을 하나씩 꺼냅니다. 비용은 [docs/calling-convention.md](docs/calling-convention.md)의
  측정표를 보십시오.
- 차량 수치(600 kW, 800 kg, Cd 0.9/0.8 등)는 대표값으로 정한 가정이며 실제 차량 값이 아닙니다.
- 계산은 SI(m/s)로 하고 자동차 속도는 화면에서만 km/h로 보여줍니다. 닫힘 323.5 km/h, 열림 336.5 km/h입니다.

## 출처

단계 구성 방식은 Lorena Barba의 "CFD Python: 12 Steps to Navier–Stokes"를 참고했습니다.
문장과 코드는 새로 썼습니다. F1 소재(DRS)는 윤재수, 『F1 레이스카의 공기역학』(골든래빗, 2023)에서
착안했습니다. 참고 문헌 목록은 [AGENTS.md](AGENTS.md)의 "출처와 저작권"에 있습니다.

## 라이선스

[LICENSE](LICENSE)를 따릅니다.
