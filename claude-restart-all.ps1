# Restart every Claude Code session running in Orca terminal tabs onto the newly installed
# Claude Code version, in place, keeping each tab's conversation, model and effort level.
#
# For each tab: send /exit, then in the same tab run
#   claude --resume <that session's id> --model <its model> --effort <its effort>
# Tabs that are busy, have unsent text in the prompt, have an unsent feedback draft,
# or are already on the latest version are left alone.
param(
  [string]$Only,     # only tabs whose title contains this text
  [switch]$DryRun    # print what would happen, send nothing
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$orca = (Get-Command orca -ErrorAction SilentlyContinue).Source
if (-not $orca) { $orca = "$env:LOCALAPPDATA\Programs\orca\resources\bin\orca.exe" }
$claudeHome = "$env:USERPROFILE\.claude"
$latest = ((& claude --version) -split ' ')[0]
"Installed Claude Code: $latest`n"

$terms = (& $orca terminal list --json | ConvertFrom-Json).result.terminals |
  Where-Object { $_.agentIdentity -eq 'claude' -and $_.connected -and $_.writable }

function Get-SessionFile($sid) {
  Get-ChildItem "$claudeHome\projects\*\$sid.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
}

# Orca's tab title is Claude Code's session title: the last /rename (custom-title), else the auto title (ai-title)
function Get-SessionTitle($file) {
  $custom = Select-String -Path $file -Pattern '"type":"custom-title"' | Select-Object -Last 1
  if ($custom) { return ($custom.Line | ConvertFrom-Json).customTitle }
  $ai = Select-String -Path $file -Pattern '"type":"ai-title"' | Select-Object -Last 1
  if ($ai) { return ($ai.Line | ConvertFrom-Json).aiTitle }
}

# The model and effort the session is using now, i.e. the latest of:
#   requestedModel/effort on assistant records, and the output of any later /model or /effort
function Get-SessionModelEffort($file) {
  $model = $null; $effort = $null
  foreach ($m in Select-String -Path $file -Pattern '"requestedModel":"', 'local-command-stdout>Set (model|effort)') {
    $l = $m.Line
    if ($l -match '"type":"assistant"' -and $l -match '"requestedModel":"([^"]+)"') {
      $model = $Matches[1]
      if ($l -match '"effort":"(\w+)"') { $effort = $Matches[1] }
    } elseif ($l -match 'local-command-stdout>Set model to `([^`]+)`') {
      # display name "Opus 5.5" -> claude-opus-5-5; anything else is reported as unknown
      $model = if ($Matches[1] -match '^(\w+) (\d+(?:\.\d+)*)$') { "claude-$($Matches[1].ToLower())-$($Matches[2].Replace('.', '-'))" } else { "?$($Matches[1])" }
      if ($l -match '`(low|medium|high|xhigh|max)` effort') { $effort = $Matches[1] }
    } elseif ($l -match 'local-command-stdout>Set effort level to\W*(low|medium|high|xhigh|max)') {
      $effort = $Matches[1]
    }
  }
  return $model, $effort
}

function Read-Screen($h) {
  (& $orca terminal read --terminal $h --screen --json | ConvertFrom-Json).result.terminal.tail
}

$done = 0
foreach ($f in Get-ChildItem "$claudeHome\sessions\*.json") {
  $s = Get-Content $f -Raw | ConvertFrom-Json
  $proc = Get-Process -Id $s.pid -ErrorAction SilentlyContinue
  # after an update the running binary is renamed to claude.exe.old.<n>, so match the prefix
  if (-not $proc -or $proc.ProcessName -notlike 'claude*' -or $s.kind -ne 'interactive') { continue }

  $file = Get-SessionFile $s.sessionId
  if (-not $file) { continue }
  $title = Get-SessionTitle $file
  if ($Only -and $title -notlike "*$Only*") { continue }
  $label = if ($title) { $title } else { $s.sessionId }

  if ($s.version -eq $latest) { "[skip] $label - already $latest"; continue }
  if ($s.status -ne 'idle')   { "[skip] $label - busy ($($s.status))"; continue }

  $match = @($terms | Where-Object { $_.title -eq $title })
  if ($match.Count -ne 1) { "[skip] $label - no unique Orca tab with this title ($($match.Count) found)"; continue }
  $h = $match[0].handle

  $model, $effort = Get-SessionModelEffort $file
  if (-not $model -or $model.StartsWith('?') -or -not $effort) { "[skip] $label - could not read model/effort (model=$model, effort=$effort)"; continue }

  # text left in the prompt line would get /exit appended to it
  $screen = Read-Screen $h
  $prompt = $screen | Where-Object { $_ -match '^\s*❯' } | Select-Object -Last 1
  if ($prompt -and ($prompt -replace '^\s*❯', '').Trim()) { "[skip] $label - unsent text in the prompt"; continue }
  # an unsent feedback draft makes /exit stop at "review & send / discard"; that is the user's call
  if ($screen -match 'feedback draft') { "[skip] $label - unsent feedback draft (handle it in the tab)"; continue }

  $cmd = "claude --resume $($s.sessionId) --model $model --effort $effort"
  if ($DryRun) { "[dry-run] $label - would run: $cmd"; continue }

  & $orca terminal send --terminal $h --text '/exit' --enter | Out-Null
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Process -Id $s.pid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  if (Get-Process -Id $s.pid -ErrorAction SilentlyContinue) { "[fail] $label - still running 20s after /exit, check the tab"; continue }

  & $orca terminal send --terminal $h --text $cmd --enter | Out-Null

  # wait until a new process registers the same session id on the latest version
  $deadline = (Get-Date).AddSeconds(40); $ok = $false; $trusted = $false
  while (-not $ok -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    # some folders (e.g. the home folder) ask "trust this folder?" again, and the default is "No, exit":
    # move down to "Yes" and confirm
    if (-not $trusted -and ((Read-Screen $h) -match 'Yes, I trust this folder')) {
      & $orca terminal send --terminal $h --text "$([char]27)[B" | Out-Null
      Start-Sleep -Milliseconds 500
      if (-not ((Read-Screen $h) -match '❯\s*Yes, I trust this folder')) { "[fail] $label - could not select Yes on the trust prompt, check the tab"; break }
      & $orca terminal send --terminal $h --text '' --enter | Out-Null
      $trusted = $true
    }
    $ok = [bool](Get-ChildItem "$claudeHome\sessions\*.json" | ForEach-Object { Get-Content $_ -Raw | ConvertFrom-Json } |
      Where-Object { $_.sessionId -eq $s.sessionId -and $_.version -eq $latest -and $_.pid -ne $s.pid })
  }
  if (-not $ok) { "[check] $label - relaunched, but not registered on $latest within 40s"; continue }

  # double-check the effort shown at the bottom right of the new screen ("<effort> · /effort")
  Start-Sleep -Seconds 3
  $shown = ((Read-Screen $h) | Select-String -Pattern '(low|medium|high|xhigh|max) · /effort' | Select-Object -Last 1).Matches.Groups[1].Value
  if ($shown -and $shown -ne $effort) { "[check] $label - came up with effort $shown, expected $effort"; continue }
  "[done] $label - $($s.version) -> $latest · $model · $effort"; $done++
}
"`nRestarted $done session(s)."
