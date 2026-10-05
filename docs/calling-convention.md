# 호출 규약

대상 독자: 화면(Svelte)을 만드는 사람. 이 문서만 읽고 WASM 커널을 불러 쓸 수 있어야 합니다.

## 요약

- 빌드는 `web/static/wasm/`에 `index.json`과 단계별 `stepN.wasm`, `stepN.json`(목록 파일),
  `stepN.parity.json`(일치 검사)을 만듭니다.
- 화면은 연결 모듈 `web/src/lib/gridtopinn/`만 쓰면 됩니다. 함수는 목록 파일의 이름으로 부릅니다.
- 모든 함수는 Float64와 Float32 두 벌(`<이름>_f64`, `<이름>_f32`)이 있습니다.
- 배열과 시뮬레이션 상태는 JS에서 불투명한 참조입니다. 배열 값은 하나씩 꺼내며, 원소당 약 17 ns입니다.
- 무거운 계산은 Worker 래퍼로 돌리고 프레임마다 중간 결과를 받습니다.

## 불러오기

산출물이 있는 디렉터리 URL을 인자로 넘깁니다. 사이트 기준 경로가 바뀌어도 동작합니다.

```ts
import { base } from '$app/paths';
import { loadIndex, loadStep, readVector } from '$lib/gridtopinn';

const baseUrl = `${base}/wasm`;
const index = await loadIndex(baseUrl);     // 단계 목록, 빌드 정보, 파일 크기
const step = await loadStep(baseUrl, 2);    // { manifest, exports, fn(name, precision) }

const drsRun = step.fn('drs_run', 'f64');
const tr = drsRun(2, 0.5, 1e-6, 600e3, 800, 1.225, 1.5, 0, 0.9, 0.8, 20, 80);  // 참조
const v = readVector(step, step.fn('trajectory_y', 'f64')(tr), 'f64');         // Float64Array
```

모듈은 가져오기(import) 객체 없이 인스턴스화됩니다(`WebAssembly.instantiate(bytes, {})`).
연결 모듈은 불러오는 시점에 `window`, `fetch`, `Worker`를 건드리지 않으므로 사전 렌더링 중에
가져와도 오류가 나지 않습니다. `loadStep`은 브라우저에서(예: `onMount` 안에서) 부르십시오.
`fn`은 없는 이름을 받으면 있는 이름 목록과 함께 예외를 던집니다.

## 값의 종류

| 목록 파일의 종류 | Julia | JS |
|---|---|---|
| `real` | `T` (Float64 또는 Float32) | `number` |
| `int` | `Int32` | `number` (정수) |
| `vec` | `Vector{T}` | 불투명한 참조. `readVector`, `writeVector`로 읽고 쓴다 |
| `ref:<이름>` | 구조체 (`Trajectory`, `Diffusion1D`) | 불투명한 참조. 같은 모듈의 함수에 다시 넘긴다 |

## 단위

계산과 WASM 인자, 반환값은 모두 SI입니다(속도는 m/s). 출력 = 힘 × 속도 같은 식이 그대로 성립해야 하기
때문입니다. 자동차 속도는 화면에서 km/h로 보여줍니다. 목록 파일이 해당 조작 값과 함수에
`"display": { "unit": "km/h", "scale": 3.6 }`을 붙이며, 규칙은 `표시값 = 값 × scale`입니다.
화면에서 받은 값은 `scale`로 나눠 WASM에 넘깁니다. `display`가 `null`이면 `unit` 그대로 보여줍니다.

| 값 | 계산 (m/s) | 화면 (km/h) |
|---|---|---|
| 닫힘 최고속도 | 89.86 | 323.5 |
| 열림 최고속도 | 93.46 | 336.5 |
| DRS 이득 | 3.60 | 13.0 |

`display`가 붙는 것은 1단계 `v0`, `v`, `top_speed*`, `drs_gain`, `top_speed_iterates`와 2단계 `v`,
`v_final`, `trajectory_y`, `top_speed`입니다. 3단계의 벽 속도 `U`는 m/s 그대로입니다.

참조는 만든 모듈, 만든 정밀도의 함수에만 넘길 수 있습니다. Float64로 만든 `sim`을 `_f32` 함수에
넘기면 예외가 납니다.

## 배열 전달

배열은 값을 하나씩 꺼내는 방법만 있습니다. WasmGC 배열은 JS 타입 배열로 직접 보이지 않고,
WasmTarget 0.5.3의 공식 브리지도 같은 방식을 씁니다. 모든 단계 모듈이 다음 도우미를 내보냅니다.

| 함수 | 뜻 |
|---|---|
| `vec_new(n)` | 길이 `n`인 0 벡터 |
| `vec_len(v)` | 길이 |
| `vec_get(v, i)` | `v[i]`, `i`는 1부터 |
| `vec_set(v, i, x)` | `v[i] = x` |

연결 모듈의 `readVector(step, vecRef, precision, out?)`와 `writeVector(step, values, precision)`이
이 도우미를 감쌉니다.

측정값입니다. `node wasm/bench.mjs`, WSL2, Node 26, 한 번 잰 중앙값이라 오차가 있습니다.

| 원소 수 | 읽기 f64 [ms] | 쓰기 f64 [ms] | 읽기 f32 [ms] |
|---|---|---|---|
| 1,024 | 0.04 | 0.03 | 0.02 |
| 16,384 (128²) | 0.27 | 0.32 | 0.27 |
| 65,536 (256²) | 1.10 | 1.18 | 1.10 |
| 262,144 (512²) | 4.35 | 4.81 | 4.49 |
| 1,048,576 (1024²) | 18.9 | 20.3 | 18.5 |

원소당 약 17 ns이고 네이티브 Julia(약 0.5 ns)의 30배쯤입니다. 한 프레임(16 ms) 안에 장 하나를
읽으려면 512² 정도가 한계입니다. 7단계에서 장 여러 개를 매 프레임 읽으면 256² 이하가 안전합니다.
브라우저에서의 수치는 따로 재지 않았습니다.

주의할 점이 하나 있습니다. `advance`는 `sim.u`를 새 벡터로 바꿉니다. 전진하기 전에 `field(sim)`으로
받아 둔 참조는 옛 장을 가리킵니다. 전진한 뒤에는 `field(sim)`을 다시 부르십시오.

## 상태를 가진 호출

시뮬레이션은 "만들기, n걸음 전진, 장 꺼내기, 오차 꺼내기"로 나눠 부릅니다. 3단계의 예입니다.

```ts
const p = 'f64';
const sim = step.fn('moving_wall', p)(100, 0.1, 1.0, 2e-3);    // 만들기 (N, L, U, ν)
for (let k = 0; k < 30; k++) {
  step.fn('advance', p)(sim, 1e-3, 100, 2);                    // 100걸음 전진, method 2 = RK4
  const u = readVector(step, step.fn('field', p)(sim), p);     // 현재 장
  const err = step.fn('moving_wall_error', p)(sim, 1.0);       // 해석해와의 오차
}
```

나쁜 선택은 예외를 던지지 않습니다. 안정 한계를 넘는 `Δt`를 주면 값이 커져 `Infinity`나 `NaN`이
돌아옵니다. 화면은 이것을 그대로 보여주면 됩니다. 범위를 벗어난 `method` 번호는 목록 파일의
`limits`에 적힌 기본 선택지로 동작합니다.

## 단계별 함수

정확한 인자 목록과 설명은 목록 파일이 기준입니다. 아래는 개요입니다.

| 단계 | 함수 | 대안 지점 (`method`) |
|---|---|---|
| 1 | `top_speed_iterates`, `top_speed`, `top_speed_analytic`, `drs_gain`, `power_balance`, `power_balance_derivative` | 미분 방법: 1 손 유도, 2 전진차분, 3 중심차분, 4 이중수 |
| 2 | `drs_run`, `trajectory_t`, `trajectory_y`, `settling_time`, `acceleration`, `top_speed` | 적분기: 1 Euler, 2 RK4, 3 적응형 Dormand–Prince |
| 3 | `moving_wall`, `sin_mode`, `advance`, `field`, `time`, `moving_wall_error`, `sin_mode_error`, `max_abs`, `erfc`, `stokes_first_solution`, `diffusion_depth` | 적분기: 1 Euler, 2 RK4, 3 Crank–Nicolson |

정답 데이터는 함수로 내보냅니다. 1단계 `top_speed_analytic`, 3단계 `stokes_first_solution`,
`sin_mode_error`가 해석해입니다. 2단계의 정답은 1단계 `top_speed`(열림 Cd)이며 2단계 모듈에도
들어 있습니다. 문헌 표(Ghia 등)는 7단계에서 추가합니다.

## 목록 파일 (`stepN.json`)

화면은 이 파일로 조작 요소를 만듭니다. 빌드가 `wasm/entries/stepN.jl`의 선언에서 생성합니다.

```jsonc
{
  "schema": 1, "step": 3, "title": "확산", "question": "벽이 움직이면 …",
  "wasm": "step3.wasm", "precisions": ["f64", "f32"],
  "functions": [{
    "name": "advance",
    "exports": { "f64": "advance_f64", "f32": "advance_f32" },
    "args": [{ "name": "sim", "type": "ref:Diffusion1D" }, { "name": "Δt", "type": "real" },
             { "name": "nsteps", "type": "int" }, { "name": "method", "type": "int" }],
    "returns": "real", "doc": "…", "display": null,
    "source": { "file": "src/step3/simulation.jl", "lines": [64, 75] }
  }],
  "parameters": [{
    "name": "ν", "unit": "m²/s", "default": 1e-6, "min": 1e-9, "max": 0.1, "doc": "…",
    "presets": [{ "label": "물", "value": 1e-6 }, { "label": "꿀", "value": 2e-3 }],
    "used_by": ["moving_wall", "stokes_first_solution", "diffusion_depth"], "display": null,
    "source": { "file": "src/step3/simulation.jl", "lines": [19, 28] }
  }],
  "alternatives": [{
    "id": "integrator", "title": "시간 적분기", "arg": "method", "used_by": ["advance"],
    "options": [{ "value": 1, "key": "euler", "label": "Euler (명시적, 1차)",
                  "source": { "file": "src/step3/simulation.jl", "lines": [41, 47] } }]
  }],
  "sources": [{ "file": "src/step3/simulation.jl",
                "definitions": [{ "name": "advance!", "kind": "function", "lines": [64, 75] }] }],
  "requirements": ["…"], "limits": ["…"]
}
```

- 줄 범위는 1부터 세고 양 끝을 포함하며 문서 문자열을 포함합니다. 커널 파일을 파싱해 채우므로
  소스가 바뀌면 빌드할 때 따라 바뀝니다. 위 예의 숫자는 예시입니다.
- 인자 이름은 커널의 유니코드 이름(`ρ`, `Δt`, `ν`)을 그대로 씁니다. 내보내기 이름은 ASCII입니다.
- `parameters[].source`는 그 값을 인자로 받는 커널 정의를 가리킵니다. 줄 안에서의 위치(열)는 없습니다.
  화면이 숫자를 코드 안에 겹쳐 보여주려면 인자 이름으로 찾아야 합니다.
- 브리지 도우미(`vec_*`)의 `source`는 `null`입니다.
- `sources`는 그 단계가 쓰는 모든 커널 파일의 정의 목록입니다. 앞 단계에서 재사용한 파일도 들어 있어서
  "접힌 블록"으로 보여줄 수 있습니다.

## 소스 표시

화면에 보이는 소스는 컴파일에 쓴 `.jl` 파일입니다. `web/src/lib/sources.ts`의 `sourceText({file, lines})`가
Vite의 `?raw` 가져오기로 `src/**/*.jl`을 읽고 줄 범위를 잘라 돌려줍니다. 표시용 사본은 없습니다.
이 모듈은 Vite에 의존하므로 연결 모듈 밖에 있습니다.

## Worker 래퍼

Worker는 호출하는 쪽이 만들어 넘깁니다. 연결 모듈은 번들러에 의존하지 않습니다.

```ts
import { createClient } from '$lib/gridtopinn';

const worker = new Worker(new URL('$lib/gridtopinn/worker.ts', import.meta.url), { type: 'module' });
const client = createClient(worker);
await client.load(baseUrl, 3);

const sim = await client.call('moving_wall', 'f64', [100, 0.1, 1.0, 2e-3]);   // { handle: 1 }
const run = client.run({
  fn: 'advance', precision: 'f64', args: [sim, 1e-3, 100, 2], frames: 30,
  vectors: [{ fn: 'field', args: [sim] }],                    // 프레임마다 다시 꺼내 읽을 벡터
  scalars: [{ fn: 'moving_wall_error', args: [sim, 1.0] }],   // 프레임마다 계산할 값
  onFrame: (f) => draw(f.vectors[0], f.scalars[0]),           // f.frame = 1, 2, …
});
await run.done;          // { frames, stopped }. 도중에 멈추려면 run.stop()
await client.release([sim]);
```

참조는 Worker 밖으로 나오지 못하므로 양쪽에서 `{ handle: number }`로 표현합니다. 실제 참조는 Worker 안의
표에 있고, `release`로 지웁니다.

메시지 형식입니다. 모든 요청에는 `id`가 있고 응답은 같은 `id`로 옵니다.

| 요청 `op` | 필드 | 성공 응답의 `result` |
|---|---|---|
| `load` | `baseUrl`, `step` | `{ manifest }` |
| `call` | `fn`, `precision`, `args` | 숫자 또는 `{ handle }` |
| `read` | `handle`, `precision` | 타입 배열 (전송됨) |
| `release` | `handles` | 없음 |
| `run` | `fn`, `precision`, `args`, `frames`, `vectors?`, `scalars?` | `{ frames, stopped }` |
| `stop` | `target` (run의 `id`) | 없음 |

응답은 세 가지입니다.

```ts
{ id, type: 'ok', result? }
{ id, type: 'frame', frame, result, vectors: TypedArray[], scalars: number[] }   // run 중 프레임마다
{ id, type: 'error', message }
```

`args`의 원소는 숫자 또는 `{ handle }`입니다. `vectors`의 원소는 `{ handle }` 또는 `{ fn, args }`입니다.
오류는 항상 `error` 응답으로 오고 `client`의 Promise가 reject됩니다. 응답 없이 멈추지 않습니다.
Worker의 처리 로직은 `handler.ts`에 순수 함수로 있어서 Node에서 테스트합니다.

## 브라우저 요구사항

WebAssembly GC를 지원하는 브라우저가 필요합니다. 최소 버전은 이 저장소에서 확인하지 않았습니다.
배포 전에 <https://webassembly.org/features/>의 "Garbage collection" 행을 확인하십시오.
실행을 확인한 환경은 Node 26과 개발 환경(WSL2)의 Chrome입니다. Firefox와 Safari에서는 실행하지 않았습니다.

## 크기와 속도

`julia +1.12 --project=wasm wasm/build.jl`, WasmTarget 0.5.3, 최적화 후 크기입니다.

| 모듈 | 크기 |
|---|---|
| `step1.wasm` | 34.1 KiB |
| `step2.wasm` | 74.7 KiB |
| `step3.wasm` | 70.8 KiB |

커널 실행 시간입니다. `node wasm/bench.mjs`와 `julia +1.12 --project=wasm wasm/bench.jl`,
WSL2에서 한 번 잰 중앙값입니다.

| 커널 | WASM f64 [ms] | 네이티브 f64 [ms] |
|---|---|---|
| 1단계 `top_speed` 1000회 | 0.15 | 0.13 |
| 2단계 `drs_run` RK4 8000걸음 | 0.31 | 0.38 |
| 3단계 `advance` RK4, N=200, 1000걸음 | 4.7 | 1.3 |

스칼라 계산은 네이티브와 비슷하고, 걸음마다 배열을 새로 만드는 3단계는 3~4배 느립니다.

## 검증

| 명령 | 확인하는 것 |
|---|---|
| `node wasm/check_parity.mjs` | 모든 내보내기와 대안, 두 정밀도가 네이티브와 같은 값을 내는지 (Node) |
| `cd web && bun run test` | 같은 검사를 연결 모듈로, 그리고 Worker 처리 로직 |
| `cd web && bun run test:e2e` | 빌드한 사이트를 Chrome으로 열어 `/`와 `/verify`를 검사 |

허용 오차는 상대 1e-12(Float64), 1e-5(Float32)입니다. 현재 결과는 64개 사례, 비교 452건에서 불일치 0건이고
최대 상대 차이도 0입니다.

e2e는 기준 경로 `/`와 `/sub` 두 번 실행하며 다음 중 하나라도 어긋나면 실패합니다.
콘솔 에러와 실패한 요청이 없을 것, 단계별 일치 검사 실패가 0건일 것, 그림마다 배경이 아닌 픽셀이 있을 것,
3단계 Worker의 프레임이 중간 값을 거쳐 30에 도달할 것, 그린 곡선과 해석해의 차이가 커널이 보고한 오차와 같을 것,
적분기와 정밀도를 바꾸면 결과가 바뀔 것, `.wasm` 요청이 기준 경로 아래로 나갈 것.
스크린샷은 `web/test-results/screenshots/`에 남습니다.

## 알려진 한계

- 배열은 값을 하나씩 꺼냅니다. 위 측정표의 한계를 넘는 격자는 매 프레임 읽지 마십시오.
- 전진한 뒤에는 `field(sim)`을 다시 불러야 합니다. 예전 참조는 옛 장을 가리킵니다.
- `integrate_adaptive`는 걸음마다 `push!`를 씁니다. WASM에서는 `push!`가 배열 전체를 복사하므로
  걸음 수가 수천을 넘으면 느려집니다. 기본 설정에서는 약 26걸음입니다.
- Float32의 Newton 수렴 판정과 적응형 `rtol = 1e-6`은 Float32 정밀도 근처라 흔들릴 수 있습니다.
- 차량 수치와 조작 값의 범위는 대표값으로 정한 가정입니다. 화면에서 아직 써 보지 않았습니다.
- 개발 서버(`bun run dev`)는 페이지, `.wasm`, `.jl` 소스가 HTTP 200으로 응답하는 것만 손으로 확인했습니다.
  e2e는 빌드 결과만 검사합니다.
