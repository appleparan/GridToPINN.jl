// Nine-step curriculum text, copied from the "단계 구성" table in AGENTS.md.
// For built steps the title and question must equal the wasm manifest (enforced by tests).
export interface CurriculumStep {
	step: number;
	title: string;
	question: string;
	method: string;
}

export const CURRICULUM: readonly CurriculumStep[] = [
	{ step: 1, title: '미분과 Newton법', question: 'DRS를 열면 최고속도가 얼마나 오르나', method: '유한차분, 이중수 자동미분, Newton법' },
	{ step: 2, title: '시간 전진', question: '그 속도에 도달하는 데 얼마나 걸리나', method: 'Euler, RK4, 간격을 스스로 조절하는 RK' },
	{ step: 3, title: '확산', question: '벽이 움직이면 물과 꿀 중 어느 쪽이 더 깊이 끌려오나', method: '공간만 차분하고 2단계 적분기 재사용' },
	{ step: 4, title: '대류', question: '옮기기만 하는데 왜 모양이 망가지나. 빠른 유체가 느린 유체를 따라잡으면 어떻게 되나', method: '유한체적, 기울기 제한자, SSP-RK3' },
	{ step: 5, title: 'Poisson', question: '소용돌이 중심은 왜 압력이 낮은가', method: 'Jacobi에서 다중격자로' },
	{ step: 6, title: 'Staggered grid와 발산 제거', question: '비압축성 유동에서 압력은 무슨 일을 하나', method: 'MAC 격자, 투영' },
	{ step: 7, title: '조립', question: '뚜껑만 미끄러지는 상자 안에서 유체는 어떻게 도나', method: '2~6단계 부품 조립' },
	{ step: 8, title: 'PINN', question: '센서 몇 개의 값만으로 유동 전체를 맞힐 수 있나', method: '직접 짠 신경망, 자동미분' },
	{ step: 9, title: 'GPU (선택)', question: '같은 코드를 GPU로 옮기면 언제 빨라지나', method: 'GPU용 커널' }
];
