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

test('Step3 WASM: Crank–Nicolson — 무조건 안정 (음해법)', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await loadWasm(page);
  const r = await page.evaluate(async () => {
    const e = await window.__wasmReady;

    const N = 20;           // y ∈ [0,1], Δy = 0.05
    const alpha = 0.01;
    const dx = 0.05;
    const limit = dx * dx / (2 * alpha);   // 0.125 (명시적 Euler 한계)

    // sin(πy) 초기조건 (안정·정확도 확인용)
    const setup = () => {
      const u = e.vec_new(BigInt(N + 1));
      for (let i = 1; i <= N + 1; i++) {
        const y = (i - 1) * dx;
        e.vec_set(u, BigInt(i), Math.sin(Math.PI * y));
      }
      return u;
    };
    // 스파이크 초기조건 (고주파 모드 함유 — 발산·링 확인용, 네이티브 테스트와 동일)
    const setupSpike = () => {
      const u = e.vec_new(BigInt(N + 1));
      for (let i = 1; i <= N + 1; i++) e.vec_set(u, BigInt(i), 0.0);
      e.vec_set(u, 2n, 1.0);   // 두 번째 격자점에 스파이크
      return u;
    };

    // CN: Δt = 8× 한계(1.0) × 20스텝 — 발산하지 않아야 함
    const uCN = setup();
    e.diffuse_advance(uCN, 8 * limit, alpha, dx, 20n, 3n);

    // Euler: 같은 Δt × 10스텝, 스파이크 초기조건 — 발산
    const uEuler = setupSpike();
    e.diffuse_advance(uEuler, 8 * limit, alpha, dx, 10n, 1n);

    // CN 링: 스파이크 초기조건 × 11스텝 — 발산은 없지만 음수 값(링) 발생
    const uRing = setupSpike();
    e.diffuse_advance(uRing, 8 * limit, alpha, dx, 11n, 3n);
    let minRing = Infinity;
    let maxRing = -Infinity;
    for (let i = 1; i <= N + 1; i++) {
      const v = e.vec_get(uRing, BigInt(i));
      minRing = Math.min(minRing, v);
      maxRing = Math.max(maxRing, v);
    }

    // CN 정확도: Δt=0.5 ×2스텝, 해석해 sin(πy)·e^(−απ²t) 대비
    const uAcc = setup();
    e.diffuse_advance(uAcc, 0.5, alpha, dx, 2n, 3n);
    let maxErr = 0;
    for (let i = 1; i <= N + 1; i++) {
      const y = (i - 1) * dx;
      const exact = Math.sin(Math.PI * y) * Math.exp(-alpha * Math.PI * Math.PI);
      maxErr = Math.max(maxErr, Math.abs(e.vec_get(uAcc, BigInt(i)) - exact));
    }

    return {
      cnMax: e.max_abs(uCN),
      eulerMax: e.max_abs(uEuler),
      cnAccErr: maxErr,
      minRing, maxRing,
    };
  });

  // CN: 8× 한계에서도 발산하지 않음 (초기 최대 1 이하로 감쇠)
  expect(r.cnMax).toBeLessThanOrEqual(1.000000001);
  // Euler: 같은 Δt에서 발산
  expect(r.eulerMax).toBeGreaterThan(1e6);
  // CN 링: 발산은 없지만 최대원리 위반 (음수 값)
  expect(r.minRing).toBeLessThan(0);
  expect(r.maxRing).toBeLessThanOrEqual(1.000001);
  // CN 큰 Δt에서도 해석해 오차 1.7e-4 수준
  expect(r.cnAccErr).toBeLessThan(0.001);
  await browser.close();
});

test('Step3 WASM: 매끄러움 → 잠복 → 발산 (깨뜨리기 삼단 서사)', async () => {
  const browser = await launchChrome();
  const page = await browser.newPage();
  await loadWasm(page);
  const r = await page.evaluate(async () => {
    const e = await window.__wasmReady;

    const N = 20;
    const alpha = 0.01;
    const dx = 0.05;
    const dt = 0.3;   // 명시적 한계 0.125의 2.4배

    // 초기조건: 매끄러운 sin(πy) + 눈에 안 보이는 고주파 sin(9πy)·1e-3
    const u0 = new Array(N + 1);
    for (let i = 0; i <= N; i++) {
      const y = i * dx;
      u0[i] = Math.sin(Math.PI * y) + 1e-3 * Math.sin(9 * Math.PI * y);
    }

    // 한 스텝씩 30번 전진하며 기록 (중간 결과를 계속 꺼내는 상태형 호출 패턴)
    const u = e.vec_new(BigInt(N + 1));
    for (let i = 0; i <= N; i++) e.vec_set(u, BigInt(i + 1), u0[i]);
    const hist = [];
    for (let s = 1; s <= 30; s++) {
      e.diffuse_advance(u, dt, alpha, dx, 1n, 1n);  // Euler 1스텝
      hist.push(e.max_abs(u));
    }

    // 스텝 30 프로파일 (톱니 확인)
    const profile30 = [];
    for (let i = 1; i <= N + 1; i++) profile30.push(e.vec_get(u, BigInt(i)));

    // CN 같은 조건: 정상
    const uCN = e.vec_new(BigInt(N + 1));
    for (let i = 0; i <= N; i++) e.vec_set(uCN, BigInt(i + 1), u0[i]);
    e.diffuse_advance(uCN, dt, alpha, dx, 30n, 3n);
    let cnMax = 0;
    for (let i = 1; i <= N + 1; i++) {
      cnMax = Math.max(cnMax, Math.abs(e.vec_get(uCN, BigInt(i))));
    }

    return { hist, profile30, cnMax };
  });

  // 삼단 서사: 감쇠 → 전환 → 발산
  const hist = r.hist;
  expect(hist[24]).toBeGreaterThan(0.4);   // 25스텝: 여전히 매끄러운 크기
  expect(hist[24]).toBeLessThan(0.5);
  expect(Math.min(...hist.slice(0, 27))).toBeGreaterThan(0.4);  // 잠복기 발산 없음
  expect(hist[29]).toBeCloseTo(6.645961359408092, 4);           // 스텝 30: 톱니 발산

  // 스텝 30 프로파일: 인접 부호 반대 (톱니)
  const sgn = (x: number) => Math.sign(x);
  expect(sgn(r.profile30[1])).not.toBe(sgn(r.profile30[2]));
  expect(sgn(r.profile30[9])).not.toBe(sgn(r.profile30[10]));

  // CN은 같은 상황에서 정상
  expect(r.cnMax).toBeLessThan(0.5);
  await browser.close();
});
