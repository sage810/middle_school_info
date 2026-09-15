# 신현중학교 정보 · 학생용 수업 사이트

GitHub Pages로 배포하는 수업 사이트입니다. `index.html`에서 차시(1~15차시)로 이동합니다.

- 배포 주소: https://sage810.github.io/middle_school_info/
- 디자인: `pages/design-handoff` 캔버스 디자인(파스텔 카드 + 굵은 테두리 + 그림자, CookieRun·Maplestory·GangwonEdu 폰트)을 그대로 옮겨왔습니다.

## 폴더 구조

- `index.html` — 차시 목록 페이지
- `lesson01.html` ~ `lesson15.html` — 차시별 페이지 (현재는 빈 틀만 있는 상태, 내용을 채워야 함)
- `assets/style.css` — 공통 스타일
- `assets/fonts/` — 로컬로 내장한 웹폰트

## 새 차시 내용 채우기

`lessonNN.html`을 열어 `<h1 class="big">제목을 입력하세요</h1>`와 `<p class="mini">...</p>`, 그리고
`<div class="placeholder-box">CONTENT COMING SOON</div>` 부분을 실제 활동 내용으로 바꾸면 됩니다.
`index.html`의 해당 카드에서도 `card-title`, `card-desc` 문구를 함께 갱신해 주세요.
