# data/ — 신현중학교 시간표 · 급식 데이터

나이스(NEIS) 교육정보 개방 포털 API로 받은 데이터. `scripts/fetch-neis.ps1` 이 생성한다.

- 학교: 신현중학교 (경기도교육청 `J10` / 행정표준코드 `7692151`)
- 최종 생성 시각은 각 JSON 의 `generatedAt` 필드 참고

## 다시 받기

```powershell
# 1) 최초 1회: 인증키 파일 만들기 (git 추적 제외됨)
Copy-Item scripts/neis.local.ps1.example scripts/neis.local.ps1
#    scripts/neis.local.ps1 을 열어 실제 인증키 입력

# 2) 실행 (PowerShell 7)
pwsh scripts/fetch-neis.ps1
pwsh scripts/fetch-neis.ps1 -TimetableWeeks 3 -MealMonth 202610   # 옵션 예시
```

인증키는 환경변수 `NEIS_TIMETABLE_KEY`, `NEIS_MEAL_KEY` 로 넘겨도 된다.
API 인증키는 절대 커밋/푸시하지 않는다.

## 파일

### school.json
학교 기본 정보 + 학년별 반 목록 (`schoolInfo`, `classInfo`).

### timetable.json — 중학교시간표 (`misTimetable`)
이번 주 월요일부터 `TimetableWeeks` 주(기본 2주), 주말 제외.

```jsonc
{
  "range": { "from": "2026-08-31", "to": "2026-09-13" },
  "maxPeriod": 7,
  "classes": {
    "1": {                       // 학년
      "1": {                     // 반
        "2026-09-01": { "periods": ["과학","도덕","음악","체육","수학","국어","동아리활동"] },
        "2026-09-05": { "holiday": "토요휴업일" }   // 수업 없는 날
      }
    }
  }
}
```

- `periods` 배열 인덱스 0 = 1교시. 빈 문자열은 해당 교시 수업 없음.
- NEIS 가 같은 교시를 빈 값과 함께 중복으로 주는 경우가 있어, 값이 있는 쪽을 채택해 중복 제거함.

### meal.json — 급식식단정보 (`mealServiceDietInfo`)
`MealMonth` 한 달치(기본: 이번 달). 급식이 없는 날(주말·공휴일)은 키 자체가 없음.

```jsonc
{
  "month": "2026-09",
  "days": {
    "2026-09-01": [
      {
        "type": "중식",
        "dishes": [
          { "name": "쇠고기미역국", "raw": "쇠고기미역국.중.신 (5.6.13.16)", "allergens": [5,6,13,16] }
        ],
        "kcal": 803.7,
        "nutrients": { "탄수화물(g)": "77.5", "단백질(g)": "39.2", "...": "..." },
        "origin": ["쇠고기(종류) : 국내산(한우)", "..."],
        "headcount": 950
      }
    ]
  }
}
```

- `name` = 표시용으로 정리한 이름. `raw` = NEIS 원문(배식표식 `.중`, 내부코드 `(S)` 등 포함).
- `allergens` = 식품알레르기 유발식재료 번호.

## 알레르기 번호 (식품알레르기 유발식품 표시 기준, 19종)

| 번호 | 식재료 | 번호 | 식재료 |
|---|---|---|---|
| 1 | 난류(가금류) | 11 | 복숭아 |
| 2 | 우유 | 12 | 토마토 |
| 3 | 메밀 | 13 | 아황산류 |
| 4 | 땅콩 | 14 | 호두 |
| 5 | 대두 | 15 | 닭고기 |
| 6 | 밀 | 16 | 쇠고기 |
| 7 | 고등어 | 17 | 오징어 |
| 8 | 게 | 18 | 조개류(굴, 전복, 홍합 포함) |
| 9 | 새우 | 19 | 잣 |
| 10 | 돼지고기 | | |
