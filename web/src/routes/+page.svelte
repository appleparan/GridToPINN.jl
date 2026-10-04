<script lang="ts">
  import { data } from "./+page";
</script>

<main style="padding: 2rem; max-width: 800px; margin: 0 auto; font-family: system-ui;">
  <h1>Grid to PINN — WASM 시험 페이지</h1>

  <section>
    <h2>상태</h2>
    <p>{data.status}</p>
    <p style="color: #666; white-space: pre-wrap;">{data.note}</p>
  </section>

  <section>
    <h2>향후 이 페이지에 넣을 내용</h2>
    <ul>
      <li>각 단계 WASM을 불러 실행</li>
      <li>계산 결과 숫자 표시</li>
      <li>간단한 결과 그림(캔버스/SVG)</li>
      <li>정답과의 오차·통과 여부 표시</li>
    </ul>
  </section>
</main>
