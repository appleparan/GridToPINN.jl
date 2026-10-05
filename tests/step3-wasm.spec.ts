import { test, expect, chromium } from '@playwright/test';
import fs from 'fs';
import path from 'path';

const WASM_PATH = path.resolve(__dirname, '../web/public/step1.wasm');
const WASM_B64 = fs.readFileSync(WASM_PATH).toString('base64');
const WASM_DATA_URL = `data:application/wasm;base64,${WASM_B64}`;

// Step3 참조값 (네이티브 Julia와 비트 단위 일치 확인됨):
//   erfc 근사(A&S 7.1.26): |오차| ≤ 1.5e-7 — erfc(0) = 0.999999999 (정확히 1 아님)
//   δ_water(ν=1e-6, t=1) = 2e-3 m, δ_honey(ν=2e-3, t=1) ≈ 0.0894427 m
//   깊이 비 = √2000 ≈ 44.7214 — 꿀이 물보다 45배 깊이 끌려온다 (핵심 질문의 답)
//   물: y∈[0,0.02], N=200, RK4 Δt=1e-3 ×1000 → u(δ) ≈ erfc(1)·U, 최대오차 < 0.05
//   깨뜨리기: N=20, α=0.01, dx=0.05, Euler 한계 Δt=0.125;
//     Δt=0.5(4배) ×30스텝 → max|u| > 1e6, Δt=0.1125(0.9배) ×40스텝 → 안정

// WASM 모듈을 인스턴스화해서 e (exports)를 반환하는 Promise
function loadWasm(page: any) {
  return page.setContent(`<!DOCTYPE html><html><body><script>
    window.__wasmReady = (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      return instance.exports;
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });
}

async function launchChrome() {
  return chromium.launch({
    executablePath: '/usr/bin/google-chrome-stable',
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-web-security'],
  });
}

test('Step3 WASM: erfc 근사 정확도', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await loadWasm(page);
  const r = await page.evaluate(async () => {
    const e = await window.__wasmReady;
    return {
      erfc0: e.erfc(0.0),
      erfc1: e.erfc(1.0),
      erfcHalf: e.erfc(0.5),
      erfc2: e.erfc(2.0),
      erfcNeg1: e.erfc(-1.0),
    };
  });
  // erfc(0) = 0.999999999 — A&S 근사 특성상 정확히 1이 아님 (허용 오차 내)
  expect(Math.abs(r.erfc0 - 1)).toBeLessThan(2e-7);
  expect(Math.abs(r.erfc1 - 0.15729920705028513)).toBeLessThan(2e-7);
  expect(Math.abs(r.erfcHalf - 0.4795001221869535)).toBeLessThan(2e-7);
  expect(Math.abs(r.erfc2 - 0.004677734981047265)).toBeLessThan(2e-7);
  expect(Math.abs(r.erfcNeg1 - (2 - 0.15729920705028513))).toBeLessThan(2e-7);
  await browser.close();
});

test('Step3 WASM: 확산 깊이 — 물 vs 꿀 (질문의 답)', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await loadWasm(page);
  const r = await page.evaluate(async () => {
    const e = await window.__wasmReady;
    const dWater = e.diffusion_depth(1e-6, 1.0);
    const dHoney = e.diffusion_depth(2e-3, 1.0);
    return {
      dWater, dHoney,
      ratio: dHoney / dWater,
      // 확산 깊이에서 벽 속도의 16%가 남는다: u(δ,t)/U = erfc(1)
      uAtDepthWater: e.stokes_first(dWater, 1.0, 1.0, 1e-6),
      uAtDepthHoney: e.stokes_first(dHoney, 1.0, 1.0, 2e-3),
    };
  });
  expect(r.dWater).toBeCloseTo(2e-3, 12);
  expect(r.dHoney).toBeCloseTo(0.08944271909999159, 10);
  expect(r.ratio).toBeCloseTo(44.721359549995796, 6);
  expect(r.uAtDepthWater).toBeCloseTo(0.15729920705028513, 6);
  expect(r.uAtDepthHoney).toBeCloseTo(0.15729920705028513, 6);
  await browser.close();
});

test('Step3 WASM: 움직이는 벽 (물) — 해석해와 비교', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await loadWasm(page);
  const r = await page.evaluate(async () => {
    const e = await window.__wasmReady;

    // 물: y∈[0,0.02] m, N=200 (Δy=1e-4), 벽을 t=0에 U=1로 순간 이동
    const N = 200;
    const u = e.vec_new(BigInt(N + 1));
    for (let i = 1; i <= N + 1; i++) e.vec_set(u, BigInt(i), i === 1 ? 1.0 : 0.0);
    // RK4, Δt=1e-3 s ×1000스텝 → t=1 s
    e.diffuse_advance(u, 1e-3, 1e-6, 1e-4, 1000n, 2n);

    // 해석해와 비교
    let maxErr = 0;
    const profile = [];
    for (let i = 0; i <= N; i++) {
      const y = i * 1e-4;
      const exact = e.stokes_first(y, 1.0, 1.0, 1e-6);
      const num = e.vec_get(u, BigInt(i + 1));
      maxErr = Math.max(maxErr, Math.abs(num - exact));
      if (i % 40 === 0) profile.push(num);
    }
    return {
      wall: e.vec_get(u, 1n),
      atDepth: e.vec_get(u, 21n),   // y = 2e-3 = δ → u/U = erfc(1) ≈ 0.1573
      farField: e.vec_get(u, 201n), // y = 0.02 m ≫ δ → ≈ 0
      maxErr,
      profile,
    };
  });
  expect(r.wall).toBe(1.0);
  expect(r.atDepth).toBeCloseTo(0.15729920705028513, 2);
  expect(Math.abs(r.farField)).toBeLessThan(1e-9);
  // 단조 감소 프로파일 (0.02 m 간격 샘플)
  for (let i = 1; i < r.profile.length; i++) {
    expect(r.profile[i]).toBeLessThanOrEqual(r.profile[i - 1] + 1e-12);
  }
  expect(r.maxErr).toBeLessThan(0.05);
  await browser.close();
});

test('Step3 WASM: 깨뜨리기 — 큰 Δt에서 확산 발산', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await loadWasm(page);
  const r = await page.evaluate(async () => {
    const e = await window.__wasmReady;

    const N = 20;           // y ∈ [0,1], Δy = 0.05
    const alpha = 0.01;
    const dx = 0.05;
    const limit = dx * dx / (2 * alpha);   // 0.125 (명시적 Euler 한계)

    // 안정: 한계의 0.9배 × 40스텝 (sin(πy) 초기조건)
    const uStable = e.vec_new(BigInt(N + 1));
    for (let i = 1; i <= N + 1; i++) {
      const y = (i - 1) * dx;
      e.vec_set(uStable, BigInt(i), Math.sin(Math.PI * y));
    }
    e.diffuse_advance(uStable, 0.9 * limit, alpha, dx, 40n, 1n);

    // 발산: 한계의 4배 × 30스텝 (빠른 모드가 반올림 오차에서 자라 ×7/스텝)
    const uDiverge = e.vec_new(BigInt(N + 1));
    for (let i = 1; i <= N + 1; i++) {
      const y = (i - 1) * dx;
      e.vec_set(uDiverge, BigInt(i), Math.sin(Math.PI * y));
    }
    e.diffuse_advance(uDiverge, 4 * limit, alpha, dx, 30n, 1n);

    return {
      limit,
      stableMax: e.max_abs(uStable),
      divergeMax: e.max_abs(uDiverge),
    };
  });
  expect(r.limit).toBeCloseTo(0.125, 12);
  // 한계 이하: 최대원리 (초기 최대 1를 넘지 않음)
  expect(r.stableMax).toBeLessThanOrEqual(1.000000001);
  // 한계의 4배: 발산
  expect(r.divergeMax).toBeGreaterThan(1e6);
  await browser.close();
});
