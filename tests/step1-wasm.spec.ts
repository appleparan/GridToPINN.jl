import { test, expect, chromium } from '@playwright/test';
import fs from 'fs';
import path from 'path';

const WASM_PATH = path.resolve(__dirname, '../web/public/step1.wasm');
const WASM_B64 = fs.readFileSync(WASM_PATH).toString('base64');
const WASM_DATA_URL = `data:application/wasm;base64,${WASM_B64}`;

test('Step1 WASM 로드 및 기본 스칼라 함수 호출', async () => {
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome-stable',
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-web-security'],
  });

  // data:text/html 페이지에서 WASM을 data URL로 로드
  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;

      const result = {
        fx: e.f_poly(1.0),
        dfx: e.df_analytic(1.0),
        df: e.derivative_fd(1.0, 1e-6),
        v: e.top_speed(500000.0, 1.225, 0.30, 0.55, 0.0, 1e-12, 50n),
        dv: e.compare_drs(500000.0, 1.225, 0.55, 0.0, 0.30, 0.20, 1e-12, 50n),
        vecSum: (() => {
          const v = e.vec_new(5n);
          e.vec_set(v, 1n, 1.0);
          e.vec_set(v, 2n, 2.0);
          e.vec_set(v, 3n, 3.0);
          e.vec_set(v, 4n, 4.0);
          e.vec_set(v, 5n, 5.0);
          return e.vec_sum(v);
        })(),
        vecLen: Number((() => {
          const v = e.vec_new(5n);
          return e.vec_len(v);
        })()),
        exports: Object.keys(e).sort(),
      };
      window.__wasmResult = result;
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const result = await page.evaluate(() => window.__wasmResult);
  console.log('WASM 결과:', JSON.stringify(result, null, 2));

  expect(result.fx).toBeCloseTo(4.0, 10);
  expect(result.dfx).toBeCloseTo(8.0, 10);
  expect(result.df).toBeCloseTo(8.0, 5);
  expect(result.v).toBeCloseTo(170.4, 1);
  expect(result.dv).toBeGreaterThan(0);
  expect(result.dv).toBeCloseTo(24.66, 1);
  expect(result.vecSum).toBe(15);
  expect(result.vecLen).toBe(5);
  expect(result.exports).toContain('f_poly');
  expect(result.exports).toContain('top_speed');
  expect(result.exports).toContain('vec_sum');

  await browser.close();
});

test('Step1 WASM: derivative_dual은 브라우저에서 정상 동작 (자동미분)', async () => {
  // derivative_dual(x::Float64)::Float64 는 WASM에서 f64 받아
  // 내부에서 Dual(x, 1.0) 구성 → f_poly_wasm(Dual) → .der 추출 → f64 반환.
  // JS에서 상수 number를 넘겨도 WASM 경계에서 f64로 해석되므로 정상 동작.
  // 예상 결과: derivative_dual(1.0) = f_poly_wasm′(1.0) = 3·1² + 4·1 + 1 = 8.0
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome-stable',
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-web-security'],
  });

  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;
      window.__dualResult = e.derivative_dual(1.0);
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const result = await page.evaluate(() => window.__dualResult);
  console.log('derivative_dual(1.0) =', result);
  expect(result).toBeCloseTo(8.0, 10);

  await browser.close();
});

test('Step1 WASM: vec_set/vec_get 개별 요소 읽기', async () => {
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome-stable',
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-web-security'],
  });

  const page = await browser.newPage();
  await page.setContent(`<!DOCTYPE html><html><body><script>
    (async () => {
      const bytes = await fetch('${WASM_DATA_URL}').then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      const e = instance.exports;
      const v = e.vec_new(3n);
      e.vec_set(v, 1n, 10.0);
      e.vec_set(v, 2n, 20.0);
      e.vec_set(v, 3n, 30.0);
      window.__vecResult = {
        a: e.vec_get(v, 1n),
        b: e.vec_get(v, 2n),
        c: e.vec_get(v, 3n),
        len: Number(e.vec_len(v)),
      };
    })();
  </script></body></html>`, { waitUntil: 'networkidle' });

  const vecResult = await page.evaluate(() => window.__vecResult);
  expect(vecResult.a).toBe(10);
  expect(vecResult.b).toBe(20);
  expect(vecResult.c).toBe(30);
  expect(vecResult.len).toBe(3);

  await browser.close();
});
