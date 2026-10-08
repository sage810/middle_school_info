#Requires -Version 7
<#
.SYNOPSIS
  나이스(NEIS) 교육정보 개방 포털 API로 신현중학교 시간표 / 급식표 데이터를 받아
  data/ 폴더에 JSON으로 저장한다.

.DESCRIPTION
  - 시간표: 중학교시간표(misTimetable) — 전체 학급, 이번 주 기준 N주
  - 급식:   급식식단정보(mealServiceDietInfo) — 지정한 월 전체
  - 학교/학급: schoolInfo, classInfo

  API 인증키는 소스에 넣지 않는다(보안 규칙). 아래 중 하나로 전달한다.
    1) 환경변수  NEIS_TIMETABLE_KEY , NEIS_MEAL_KEY
    2) scripts/neis.local.ps1  (git 추적 제외) — neis.local.ps1.example 참고

.EXAMPLE
  pwsh scripts/fetch-neis.ps1
  pwsh scripts/fetch-neis.ps1 -TimetableWeeks 3 -MealMonth 202610
#>
[CmdletBinding()]
param(
  [string]$OfficeCode     = 'J10',        # 시도교육청코드 (경기도교육청)
  [string]$SchoolCode     = '7692151',    # 행정표준코드
  [string]$SchoolName     = '신현중학교',
  [int]   $TimetableWeeks = 2,            # 이번 주 월요일부터 몇 주치
  [string]$MealMonth,                     # yyyyMM (기본: 이번 달)
  [string]$OutDir         = (Join-Path $PSScriptRoot '..' 'data')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# 인증키 로드
# ---------------------------------------------------------------------------
$localKeys = Join-Path $PSScriptRoot 'neis.local.ps1'
if (Test-Path $localKeys) { . $localKeys }

$ttKey   = $env:NEIS_TIMETABLE_KEY
$mealKey = $env:NEIS_MEAL_KEY
if ([string]::IsNullOrWhiteSpace($ttKey) -or [string]::IsNullOrWhiteSpace($mealKey)) {
  throw "인증키가 없습니다. 환경변수 NEIS_TIMETABLE_KEY / NEIS_MEAL_KEY 를 설정하거나 scripts/neis.local.ps1 을 만드세요 (neis.local.ps1.example 참고)."
}

$Hub = 'https://open.neis.go.kr/hub'

# ---------------------------------------------------------------------------
# 공통 호출 헬퍼
# ---------------------------------------------------------------------------
function Invoke-Neis {
  param(
    [Parameter(Mandatory)] [string] $Endpoint,
    [Parameter(Mandatory)] [hashtable] $Query
  )
  $Query['Type']   = 'json'
  $Query['pIndex'] = 1
  $Query['pSize']  = 1000
  $qs = ($Query.GetEnumerator() | ForEach-Object {
    '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value)
  }) -join '&'

  $resp = Invoke-RestMethod -Uri ("{0}/{1}?{2}" -f $Hub, $Endpoint, $qs) -TimeoutSec 30

  # 정상: { <endpoint>: [ {head:[...]}, {row:[...]} ] }
  # 데이터 없음/오류: { RESULT: { CODE, MESSAGE } }
  $body = $resp.PSObject.Properties[$Endpoint]
  if (-not $body) {
    $code = try { $resp.RESULT.CODE } catch { '(unknown)' }
    $msg  = try { $resp.RESULT.MESSAGE } catch { '(no message)' }
    if ($code -eq 'INFO-200') { return @() }   # 해당하는 데이터가 없습니다
    throw "NEIS $Endpoint 오류: $code $msg"
  }
  $result = $body.Value[0].head[1].RESULT
  if ($result.CODE -ne 'INFO-000') {
    if ($result.CODE -eq 'INFO-200') { return @() }
    throw "NEIS $Endpoint 오류: $($result.CODE) $($result.MESSAGE)"
  }
  return ,@($body.Value[1].row)
}

function Convert-BrList {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  return $Text -split '<br\s*/?>' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

# ---------------------------------------------------------------------------
# 기간 계산
# ---------------------------------------------------------------------------
$today  = (Get-Date).Date
$monday = $today.AddDays( - (([int]$today.DayOfWeek + 6) % 7) )   # 이번 주 월요일
$ttFrom = $monday
$ttTo   = $monday.AddDays(7 * $TimetableWeeks - 1)
if ([string]::IsNullOrWhiteSpace($MealMonth)) { $MealMonth = $today.ToString('yyyyMM') }
$mealFrom = [datetime]::ParseExact($MealMonth + '01', 'yyyyMMdd', $null)
$mealTo   = $mealFrom.AddMonths(1).AddDays(-1)

$ay = $today.Month -ge 3 ? $today.Year : $today.Year - 1   # 학년도(3월 시작)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$school = @{ name = $SchoolName; officeCode = $OfficeCode; schoolCode = $SchoolCode }
$stamp  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')

Write-Host "학교        : $SchoolName ($OfficeCode / $SchoolCode)"
Write-Host "학년도      : $ay"
Write-Host ("시간표 기간 : {0} ~ {1} ({2}주)" -f $ttFrom.ToString('yyyy-MM-dd'), $ttTo.ToString('yyyy-MM-dd'), $TimetableWeeks)
Write-Host ("급식 기간   : {0} ~ {1}" -f $mealFrom.ToString('yyyy-MM-dd'), $mealTo.ToString('yyyy-MM-dd'))
Write-Host ''

# ---------------------------------------------------------------------------
# 1. 학교 + 학급 정보  ->  data/school.json
# ---------------------------------------------------------------------------
Write-Host '[1/3] 학교 · 학급 정보...'
$si = Invoke-Neis 'schoolInfo' @{ KEY = $ttKey; ATPT_OFCDC_SC_CODE = $OfficeCode; SD_SCHUL_CODE = $SchoolCode }
$siRow = $si | Select-Object -First 1
$ci = Invoke-Neis 'classInfo' @{ KEY = $ttKey; ATPT_OFCDC_SC_CODE = $OfficeCode; SD_SCHUL_CODE = $SchoolCode; AY = $ay }

$grades = [ordered]@{}
foreach ($g in ($ci | Group-Object GRADE | Sort-Object { [int]$_.Name })) {
  $grades[$g.Name] = @($g.Group.CLASS_NM | Sort-Object { [int]$_ })
}

$schoolOut = [ordered]@{
  generatedAt = $stamp
  school = [ordered]@{
    name       = $SchoolName
    officeCode = $OfficeCode
    officeName = $siRow.ATPT_OFCDC_SC_NM
    schoolCode = $SchoolCode
    kind       = $siRow.SCHUL_KND_SC_NM
    address    = $siRow.ORG_RDNMA
    tel        = $siRow.ORG_TELNO
    homepage   = $siRow.HMPG_ADRES
  }
  academicYear = $ay
  grades = $grades
}
($schoolOut | ConvertTo-Json -Depth 8) | Set-Content -Path (Join-Path $OutDir 'school.json') -Encoding utf8
Write-Host ("      학급 {0}개 ({1})" -f $ci.Count, (($grades.Keys | ForEach-Object { "${_}학년 $($grades[$_].Count)반" }) -join ', '))

# ---------------------------------------------------------------------------
# 2. 시간표  ->  data/timetable.json
# ---------------------------------------------------------------------------
Write-Host '[2/3] 시간표 (학급별)...'
$classesOut = [ordered]@{}
$maxPeriod  = 0
$holidayWords = '토요휴업일','일요휴업일','휴업일','방학'

foreach ($grade in $grades.Keys) {
  $classesOut[$grade] = [ordered]@{}
  foreach ($cls in $grades[$grade]) {
    $rows = Invoke-Neis 'misTimetable' @{
      KEY = $ttKey; ATPT_OFCDC_SC_CODE = $OfficeCode; SD_SCHUL_CODE = $SchoolCode
      GRADE = $grade; CLASS_NM = $cls
      TI_FROM_YMD = $ttFrom.ToString('yyyyMMdd'); TI_TO_YMD = $ttTo.ToString('yyyyMMdd')
    }
    $days = [ordered]@{}
    foreach ($r in ($rows | Sort-Object ALL_TI_YMD, { [int]$_.PERIO })) {
      $d = [datetime]::ParseExact($r.ALL_TI_YMD, 'yyyyMMdd', $null)
      if ($d.DayOfWeek -in 'Saturday','Sunday') { continue }
      $key  = $d.ToString('yyyy-MM-dd')
      $per  = [int]$r.PERIO
      $subj = ([string]$r.ITRT_CNTNT).Trim()
      if (-not $days.Contains($key)) { $days[$key] = [ordered]@{ periods = [ordered]@{} } }
      # NEIS 가 같은 교시를 빈 값 + 실제 값으로 두 번 주는 경우가 있어, 값이 있는 쪽을 우선
      if (-not $days[$key].periods.Contains("$per") -or [string]::IsNullOrWhiteSpace($days[$key].periods["$per"])) {
        $days[$key].periods["$per"] = $subj
      }
      if ($per -gt $maxPeriod -and $subj -and $holidayWords -notcontains $subj) { $maxPeriod = $per }
    }
    # periods 해시 -> 배열, 휴업일 표시
    $daysArr = [ordered]@{}
    foreach ($k in $days.Keys) {
      $pv = $days[$k].periods
      $vals = @($pv.Values | Where-Object { $_ })
      if ($vals.Count -gt 0 -and @($vals | Where-Object { $holidayWords -contains $_ }).Count -eq $vals.Count) {
        $daysArr[$k] = [ordered]@{ holiday = $vals[0] }
      } else {
        $arr = @()
        for ($p = 1; $p -le [Math]::Max(1, ($pv.Keys | ForEach-Object { [int]$_ } | Measure-Object -Maximum).Maximum); $p++) {
          $arr += ($pv.Contains("$p") ? $pv["$p"] : '')
        }
        $daysArr[$k] = [ordered]@{ periods = $arr }
      }
    }
    $classesOut[$grade][$cls] = $daysArr
  }
  Write-Host ("      ${grade}학년 완료")
}

$ttOut = [ordered]@{
  generatedAt = $stamp
  school = $school
  range  = [ordered]@{ from = $ttFrom.ToString('yyyy-MM-dd'); to = $ttTo.ToString('yyyy-MM-dd') }
  maxPeriod = $maxPeriod
  classes = $classesOut
}
($ttOut | ConvertTo-Json -Depth 12) | Set-Content -Path (Join-Path $OutDir 'timetable.json') -Encoding utf8

# ---------------------------------------------------------------------------
# 3. 급식표  ->  data/meal.json
# ---------------------------------------------------------------------------
Write-Host '[3/3] 급식표...'
$mealRows = Invoke-Neis 'mealServiceDietInfo' @{
  KEY = $mealKey; ATPT_OFCDC_SC_CODE = $OfficeCode; SD_SCHUL_CODE = $SchoolCode
  MLSV_FROM_YMD = $mealFrom.ToString('yyyyMMdd'); MLSV_TO_YMD = $mealTo.ToString('yyyyMMdd')
}
$mealDays = [ordered]@{}
foreach ($r in ($mealRows | Sort-Object MLSV_YMD, MMEAL_SC_CODE)) {
  $d = [datetime]::ParseExact($r.MLSV_YMD, 'yyyyMMdd', $null).ToString('yyyy-MM-dd')
  if (-not $mealDays.Contains($d)) { $mealDays[$d] = @() }

  $dishes = foreach ($line in (Convert-BrList $r.DDISH_NM)) {
    $aller = @()
    $m = [regex]::Match($line, '\(([\d.\s]+)\)\s*$')
    if ($m.Success) { $aller = @($m.Groups[1].Value -split '[.\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
    # 표시용 이름: (1) '(...)' 괄호 묶음 제거 -> (2) 첫 '.' 또는 첫 '-' 이후 버림 -> (3) trim. 원본은 raw 로 보존.
    # 예) "베리무스케익.27g"->"베리무스케익", "매운돼지갈비찜(21-중-식).중 (5.6.10.13)"->"매운돼지갈비찜",
    #     "연두부찜(벌크,원통형)/양념장"->"연두부찜/양념장"
    $name = ((($line -replace '\([^)]*\)', '') -split '[.\-]', 2)[0]).Trim()
    [ordered]@{
      name      = $name
      raw       = $line
      allergens = $aller
    }
  }
  $ntr = [ordered]@{}
  foreach ($line in (Convert-BrList $r.NTR_INFO)) {
    $kv = $line -split '\s*:\s*', 2
    if ($kv.Count -eq 2) { $ntr[$kv[0].Trim()] = $kv[1].Trim() }
  }
  $kcal = $null
  $cm = [regex]::Match([string]$r.CAL_INFO, '[\d.]+')
  if ($cm.Success) { $kcal = [double]$cm.Value }

  $mealDays[$d] += [ordered]@{
    type      = $r.MMEAL_SC_NM
    dishes    = @($dishes)
    kcal      = $kcal
    nutrients = $ntr
    origin    = @(Convert-BrList $r.ORPLC_INFO)
    headcount = [double]$r.MLSV_FGR
  }
}

$mealOut = [ordered]@{
  generatedAt = $stamp
  school = $school
  month  = $mealFrom.ToString('yyyy-MM')
  range  = [ordered]@{ from = $mealFrom.ToString('yyyy-MM-dd'); to = $mealTo.ToString('yyyy-MM-dd') }
  days   = $mealDays
}
($mealOut | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $OutDir 'meal.json') -Encoding utf8
Write-Host ("      급식 {0}일치" -f $mealDays.Count)

Write-Host ''
Write-Host "완료 -> $OutDir"
Get-ChildItem $OutDir -Filter *.json | ForEach-Object { Write-Host ("  {0,-16} {1,8:N0} bytes" -f $_.Name, $_.Length) }
