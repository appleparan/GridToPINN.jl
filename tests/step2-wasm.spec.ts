import { test, expect, chromium } from '@playwright/test';
import fs from 'fs';
import path from 'path';

const WASM_PATH = path.resolve(__dirname, '../web/public/step1.wasm');
const WASM_B64 = fs.readFileSync(WASM_PATH).toString('base64');
const WASM_DATA_URL = `data:application/wasm;base64,${WASM_B64}`;

// Step2 기준값 (네이티브 Julia와 비트 단위 일치 확인됨):
//   P=50, ρ=1.225, A=0.55, Cd=0.20
//   v_top = 9.05365084869835
//   a(0)  = 74.211494...
//   euler 1스텝(dt=0.1, y=0) = 7.4211497
//   rk4   1스텝(dt=0.1, y=0) = 6.539569
//   ode_integrate(euler, t_end=0.5, dt=0.1) 최종 y = 4.3770776605041055
//   ode_integrate(rk4,   t_end=0.5, dt=0.1) 최종 y = 8.82007997835102

const P = 50.0, RHO = 1.225, A_AREA = 0.55, CD = 0.20;
const V_TOP = 9.05365084869835;

async function launchChrome() {
  return chromium.launch({
    executablePath: '/usr/bin/google-chrome-stable',
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-web-security'],
  });
}

test('Step2 WASM: acceleration, euler_step, rk4_step 스칼라 함수', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;

      const P = ${P}, rho = ${RHO}, A = ${A_AREA}, vTop = ${V_TOP};
      const result = {
        vTop: e.top_speed_target(P, rho, ${CD}, A, 1e-12, 50n),
        a0: e.acceleration(0.0, P, rho, A, vTop),
        aTop: e.acceleration(vTop, P, rho, A, vTop),
        euler1: e.euler_step(0.0, 0.1, P, rho, A, vTop),
        rk4_1: e.rk4_step(0.0, 0.1, P, rho, A, vTop),
        euler1_y: e.euler_step(3.0, 0.1, P, rho, A, vTop),
      };
      window.__result = result;
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const r = await page.evaluate(() => window.__result);

  // v_top: 네이티브와 일치 (Newton 수렴, 유효숫자 12자리)
  expect(r.vTop).toBeCloseTo(9.05365084869835, 6);
  // a(0) = P/(ρ·A) = 50/(1.225·0.55) = 74.21150278293135 (Float64, 네이티브와 동일)
  expect(r.a0).toBeCloseTo(74.21150278293135, 6);
  // a(v_top) ≈ 0 (정상상태)
  expect(Math.abs(r.aTop)).toBeLessThan(1e-9);
  // Euler 1스텝: 0 + 0.1·a(0) = 7.421150278293135
  expect(r.euler1).toBeCloseTo(7.421150278293135, 6);
  // RK4 1스텝 ≈ 6.539568953054083 (a의 감소를 반영해 Euler보다 작음)
  expect(r.rk4_1).toBeCloseTo(6.539568953054083, 6);
  // y=3에서의 Euler 1스텝 = 10.151150278293134 (네이티브와 동일)
  expect(r.euler1_y).toBeCloseTo(10.151150278293134, 8);

  await browser.close();
});

test('Step2 WASM: ode_integrate Euler vs RK4 궤적', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;

      const P = ${P}, rho = ${RHO}, A = ${A_AREA}, vTop = ${V_TOP};

      // 적분 결과는 평탄화된 Vector{Float64}: [t0, y0, t1, y1, ...]
      // vec_len/vec_get으로 요소 접근
      function readVec(v) {
        const len = Number(e.vec_len(v));
        const out = [];
        for (let i = 1n; i <= BigInt(len); i++) out.push(e.vec_get(v, i));
        return out;
      }

      const trajEuler = readVec(e.ode_integrate(0.0, 0.0, 0.5, 0.1, P, rho, A, vTop, 1n));
      const trajRK4 = readVec(e.ode_integrate(0.0, 0.0, 0.5, 0.1, P, rho, A, vTop, 2n));

      window.__result = {
        lenEuler: trajEuler.length,
        lenRK4: trajRK4.length,
        eulerFinal: trajEuler[trajEuler.length - 1],
        rk4Final: trajRK4[trajRK4.length - 1],
        eulerT0: trajEuler[0],
        eulerY0: trajEuler[1],
        rk4T0: trajRK4[0],
        rk4Y0: trajRK4[1],
      };
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const r = await page.evaluate(() => window.__result);

  // t_end=0.5, dt=0.1 → 5스텝 + 1 = 6점 × 2 (t,y) = 12
  expect(r.lenEuler).toBe(12);
  expect(r.lenRK4).toBe(12);

  // 초기값: t=0, y=0
  expect(r.eulerT0).toBe(0.0);
  expect(r.eulerY0).toBe(0.0);
  expect(r.rk4T0).toBe(0.0);
  expect(r.rk4Y0).toBe(0.0);

  // 최종값: 네이티브와 비트 단위 일치 확인된 값
  // Euler(Δt=0.1): 큰 dt로 진동하며 v_top에서 크게 벗어남 (깨뜨리기 시연)
  expect(r.eulerFinal).toBeCloseTo(4.3770776605041055, 8);
  // RK4(Δt=0.1): 안정적으로 v_top에 수렴
  expect(r.rk4Final).toBeCloseTo(8.82007997835102, 8);
  // RK4가 Euler보다 v_top(9.0537)에 훨씬 가까움
  const vTop = 9.05365084869835;
  expect(Math.abs(r.rk4Final - vTop)).toBeLessThan(Math.abs(r.eulerFinal - vTop));

  await browser.close();
});

test('Step2 WASM: 깨뜨리기 — 큰 dt에서 Euler 진동 발산', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;

      const P = ${P}, rho = ${RHO}, A = ${A_AREA}, vTop = ${V_TOP};

      function readVec(v) {
        const len = Number(e.vec_len(v));
        const out = [];
        for (let i = 1n; i <= BigInt(len); i++) out.push(e.vec_get(v, i));
        return out;
      }

      // dt = 1.0 (τ_char≈0.122s의 8배) → Euler 발산
      // y가 v_top을 넘으면 a가 음수가 되어 진동 → 진폭 증가
      const traj = readVec(e.ode_integrate(0.0, 0.0, 3.0, 1.0, P, rho, A, vTop, 1n));
      const maxAbs = Math.max(...traj.map((v, i) => i % 2 === 1 ? Math.abs(v) : 0));
      const finalY = traj[traj.length - 1];

      // RK4도 dt=1.0에서는 k3·k4가 오버플로 → NaN (네이티브 Julia와 동일 거동).
      // 적분기 선택만으로는 안정성이 보장되지 않음을 보여주는 결과.
      const trajRk4 = readVec(e.ode_integrate(0.0, 0.0, 3.0, 1.0, P, rho, A, vTop, 2n));
      const finalYRk4 = trajRk4[trajRk4.length - 1];

      window.__result = {
        maxAbs, finalY,
        rk4IsNaN: Number.isNaN(finalYRk4),
        rk4FirstStep: trajRk4[3],  // 1스텝 후 y (음수로 폭발)
      };
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const r = await page.evaluate(() => window.__result);

  // Euler(dt=1.0): 진동 발산 — |y|가 v_top의 100만 배 이상 커짐
  expect(r.maxAbs).toBeGreaterThan(1e6 * 9.05);
  // RK4(dt=1.0): 1스텝 후 이미 -6.77e25로 폭발, 이후 오버플로 → NaN
  expect(r.rk4FirstStep).toBeLessThan(-1e20);
  expect(r.rk4IsNaN).toBe(true);

  await browser.close();
});

test('Step2 WASM: Float64 일관성 — a(0)와 P/(ρ·A) 수치 일치', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;
      const P = ${P}, rho = ${RHO}, A = ${A_AREA}, vTop = ${V_TOP};

      // 유클리드 지점별 acceleration 정확성: v=0, v=v_top/2, v=v_top
      const vals = {
        half: e.acceleration(vTop / 2, P, rho, A, vTop),
        quarter: e.acceleration(vTop / 4, P, rho, A, vTop),
      };
      // 해석값: a(v) = a0·(1-(v/vTop)^3)
      const a0 = P / (rho * A);
      window.__result = {
        halfExpected: a0 * (1 - 0.125),
        halfActual: vals.half,
        quarterExpected: a0 * (1 - 1 / 64),
        quarterActual: vals.quarter,
        a0,
      };
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const r = await page.evaluate(() => window.__result);
  expect(r.halfActual).toBeCloseTo(r.halfExpected, 10);
  expect(r.quarterActual).toBeCloseTo(r.quarterExpected, 10);
  expect(r.a0).toBeCloseTo(74.21150278293135, 10);

  await browser.close();
});
