# Fetch Oliver Laszlo personal-best link and print it
$rankingsUrl = 'https://www.swimmingresults.org/12months/last12.php?Pool=L&Stroke=9&Sex=M&AgeGroup=13&date=31%2F12%2F2026&StartNumber=1&RecordsToView=50&Level=N&TargetNationality=E&TargetRegion=P&TargetCounty=XXXX&TargetClub=XXXX'

$wc = New-Object System.Net.WebClient
$wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT)'

try {
    $html = $wc.DownloadString($rankingsUrl)
} catch {
    Write-Error "Failed to download rankings page: $_"
    exit 1
}

# Extract anchors and find the one with text 'Oliver Laszlo'
$anchors = [regex]::Matches($html, '<a\b[^>]*>([^<]*)</a>')
$found = $false
foreach ($a in $anchors) {
    $text = $a.Groups[1].Value.Trim()
    if ($text -match '^Oliver\s+Laszlo$') {
        $href = $null
        $hrefIdx = $a.Value.IndexOf('href=')
        if ($hrefIdx -ge 0) {
            $after = $a.Value.Substring($hrefIdx + 5).TrimStart()
            if ($after.Length -gt 0) {
                $firstChar = $after[0]
                if ($firstChar -eq '"' -or $firstChar -eq "'") {
                    $quote = $firstChar
                    $after = $after.Substring(1)
                    $endIdx = $after.IndexOf($quote)
                    if ($endIdx -ge 0) { $href = $after.Substring(0, $endIdx) }
                } else {
                    $m = [regex]::Match($after, '^(?<u>[^\s>]+)')
                    if ($m.Success) { $href = $m.Groups['u'].Value }
                }
            }
        }
        if ($href) {
            if ($href -like '/individualbest/*' -or $href -like '/personal_best*' -or $href -notmatch '^https?://') {
                $url = 'https://www.swimmingresults.org' + $href
            } else {
                $url = $href
            }
            Write-Output "Oliver Laszlo link: $url"
            $found = $true
            break
        }
    }
}
if (-not $found) { Write-Error 'Could not find Oliver Laszlo link on the page.'; exit 2 }