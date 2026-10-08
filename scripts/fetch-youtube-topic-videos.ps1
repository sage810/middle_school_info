#Requires -Version 5.1
<#
.SYNOPSIS
  YouTube 검색어 8개에서 2025~2026년 한국 영상 40개씩 수집한다.

.DESCRIPTION
  search.list로 영상 ID를 검색한 뒤 videos.list로 통계와 영상 길이를 보강한다.
  API 키는 파일에 저장하지 않고 환경변수 또는 실행 시 입력으로 받는다.
#>
[CmdletBinding()]
param(
  [int]$PerTopic = 40,
  [string]$PublishedAfter = "2025-01-01T00:00:00Z",
  [string]$PublishedBefore = "2026-09-11T00:00:00Z",
  [string]$RegionCode = "KR",
  [string]$OutFile = (Join-Path $PSScriptRoot ".." "input" "data-analysis" "lesson-7" "youtube_topic_videos_2025_2026.csv")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$apiKey = $env:YOUTUBE_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  $apiKey = Read-Host "YouTube API key"
}
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw "YOUTUBE_API_KEY is missing."
}

$topics = @(
  @{ Label = "game"; Query = "%EA%B2%8C%EC%9E%84" },
  @{ Label = "soccer"; Query = "%EC%B6%95%EA%B5%AC" },
  @{ Label = "music"; Query = "%EC%9D%8C%EC%95%85" },
  @{ Label = "comedy"; Query = "%EC%BD%94%EB%AF%B8%EB%94%94" },
  @{ Label = "history"; Query = "%EC%97%AD%EC%82%AC" },
  @{ Label = "cooking"; Query = "%EC%9A%94%EB%A6%AC" },
  @{ Label = "entertainment"; Query = "%EC%97%94%ED%84%B0%ED%85%8C%EC%9D%B8%EB%A8%BC%ED%8A%B8" },
  @{ Label = "animation"; Query = "%EC%95%A0%EB%8B%88" }
)

function Invoke-YouTubeGet {
  param([Parameter(Mandatory)] [hashtable]$Query)
  $queryString = ($Query.GetEnumerator() | ForEach-Object {
    "{0}={1}" -f $_.Key, [uri]::EscapeDataString([string]$_.Value)
  }) -join ([string][char]38)
  Invoke-RestMethod -Uri ("https://www.googleapis.com/youtube/v3/{0}?{1}" -f $Query.Endpoint, $queryString) -TimeoutSec 30
}

function Convert-DurationToSeconds {
  param([AllowNull()] [string]$Duration)
  if ([string]::IsNullOrWhiteSpace($Duration)) { return $null }
  try { return [int][Math]::Round(([System.Xml.XmlConvert]::ToTimeSpan($Duration).TotalSeconds)) }
  catch { return $null }
}

function Get-OptionalValue {
  param([AllowNull()] [object]$Object, [Parameter(Mandatory)] [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($topic in $topics) {
  $search = Invoke-YouTubeGet @{
    Endpoint = "search"
    part = "snippet"
    type = "video"
    q = [uri]::UnescapeDataString($topic.Query)
    regionCode = $RegionCode
    relevanceLanguage = "ko"
    order = "relevance"
    publishedAfter = $PublishedAfter
    publishedBefore = $PublishedBefore
    maxResults = $PerTopic
    key = $apiKey
  }

  $videoIds = @($search.items | ForEach-Object { $_.id.videoId } | Where-Object { $_ })
  if ($videoIds.Count -eq 0) {
    Write-Warning "검색 결과 없음: $topic"
    continue
  }

  for ($offset = 0; $offset -lt $videoIds.Count; $offset += 50) {
    $batch = @($videoIds[$offset..([Math]::Min($offset + 49, $videoIds.Count - 1))])
    $details = Invoke-YouTubeGet @{
      Endpoint = "videos"
      part = "snippet,statistics,contentDetails"
      id = ($batch -join ",")
      key = $apiKey
    }

    $rank = 0
    foreach ($video in @($details.items)) {
      $rank++
      $rows.Add([pscustomobject]@{
        topic = $topic.Label
        search_rank = $rank
        video_id = $video.id
        video_url = "https://www.youtube.com/watch?v=$($video.id)"
        title = $video.snippet.title
        channel_title = $video.snippet.channelTitle
        published_at = $video.snippet.publishedAt
        category_id = $video.snippet.categoryId
        view_count = Get-OptionalValue -Object $video.statistics -Name "viewCount"
        like_count = Get-OptionalValue -Object $video.statistics -Name "likeCount"
        comment_count = Get-OptionalValue -Object $video.statistics -Name "commentCount"
        duration_iso = $video.contentDetails.duration
        duration_seconds = Convert-DurationToSeconds $video.contentDetails.duration
        collected_at = (Get-Date).ToString("yyyy-MM-dd")
      })
    }
  }
  Write-Host ("{0}: {1} items" -f $topic.Label, (@($rows | Where-Object { $_.topic -eq $topic.Label }).Count))
}

$parent = Split-Path -Parent $OutFile
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$rows | Export-Csv -LiteralPath $OutFile -NoTypeInformation -Encoding UTF8
Write-Host ("Saved: {0} ({1} rows)" -f $OutFile, $rows.Count)
