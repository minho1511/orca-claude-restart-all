# orca-claude-restart-all

Restart every Claude Code session running in your [Orca](https://github.com/stablyai/orca) tabs onto the newly installed Claude Code version **with one double-click**. Each tab keeps its conversation, its model and its effort level.

> Windows only (for now). Works with the built-in Windows PowerShell 5.1 and with PowerShell 7. Built for exactly one annoyance: [stablyai/orca#10597](https://github.com/stablyai/orca/issues/10597).

[한국어 설명은 아래에 있습니다 ↓](#한국어)

## The problem

Claude Code updates itself in the background, then every running session shows:

```
✔ Update installed · Restart to update
```

Orca deliberately keeps terminals alive in a background daemon (closing or updating Orca does not kill your agents). That's great, but it also means **your agents never pick up a new Claude Code version** until you go into every tab, `/exit`, and `claude --resume` the right conversation by hand. With 6+ tabs open that is tedious and easy to get wrong (wrong conversation, lost model, lost effort level).

Orca has no built-in "restart all agents" yet ([#10597](https://github.com/stablyai/orca/issues/10597) is open; agent-CLI updating in [#24958](https://github.com/stablyai/orca/issues/24958) was closed as not planned).

## What it does

For every Orca tab running Claude Code:

1. Finds which Claude Code session runs in that tab.
2. Reads the model and effort level that session is **currently** using.
3. Sends `/exit` to the tab, waits for the old process to exit.
4. Runs, in the same tab: `claude --resume <session-id> --model <model> --effort <effort>`.
5. If Claude Code asks "Do you trust this folder?" (it does for the home folder, and the default is **No, exit**), selects **Yes**.
6. Verifies that the session came back on the new version and that the effort shown on screen matches.

It leaves a tab alone when:

| Situation | Why |
|---|---|
| The agent is busy (working, or waiting on a question) | Never interrupt work |
| Text is typed in the prompt but not sent | `/exit` would be appended to it |
| The tab has an unsent feedback draft | `/exit` would stop at "review & send / discard". That's your call |
| Already on the latest version | Nothing to do |
| The model/effort can't be read, or the tab can't be matched uniquely | Better skip than guess |

## Usage

Requirements: Windows, Orca desktop running, `claude` on PATH. Any PowerShell: the built-in `powershell` (5.1) or `pwsh` (7). Replace `powershell` with `pwsh` below if you prefer.

```powershell
# 1) See what would happen. Sends nothing.
powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1 -DryRun

# 2) Do it
powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1

# Only tabs whose title contains some text
powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1 -Only "my-feature"
```

`-ExecutionPolicy Bypass` applies to this one run only. Windows blocks downloaded, unsigned scripts by default, so without it you get *"cannot be loaded… not digitally signed"*. Alternatively run `Unblock-File .\claude-restart-all.ps1` once. Read the script first: it's ~130 lines.

Example output:

```
Installed Claude Code: 2.1.311

[done] Refactor billing module - 2.1.310 -> 2.1.311 · claude-opus-5-5 · max
[done] Write release notes - 2.1.310 -> 2.1.311 · claude-sonnet-5-5 · high
[skip] Fix login bug - busy (busy)
[skip] Translate docs - unsent feedback draft (handle it in the tab)

Restarted 2 session(s).
```

Busy tabs are skipped, so just run it again later. Already-updated tabs are skipped too.

### Desktop shortcut (double-click)

Run once in PowerShell from the folder that holds the script:

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Restart all Claude.lnk")
$s.TargetPath = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$s.Arguments  = "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$((Resolve-Path .\claude-restart-all.ps1).Path)`""
$s.Save()
```

`GetFolderPath('Desktop')` finds the real Desktop folder whatever your Windows language is, including when OneDrive moves it.

## How it works (and how it was built)

This was built in a single session by **Claude Code (Opus 5.5)**, running inside Orca, at the request of a user who was tired of restarting tabs by hand. Everything below was measured on a live machine (Orca 1.4.242, Claude Code 2.1.310 → 2.1.311, Windows 11), not assumed.

### 1. Whose message is it?

At first glance "Update installed · Restart to update" looks like Orca's banner. Searching both binaries for the string settled it: it exists in the Claude Code binary and not in Orca's `app.asar`. Orca itself had already auto-updated (1.4.238 → 1.4.242), and all agent processes survived because they are children of Orca's terminal daemon (`daemon-host-profiles\…\Orca.exe` → `pwsh` → `claude`). So the fix has to restart **Claude Code**, not Orca.

### 2. Finding the pieces

Three data sources make it possible without touching Orca's internals:

- **`~/.claude/sessions/<pid>.json`**: Claude Code writes one file per running interactive session, with `pid`, `sessionId`, `status` (`idle` / `busy` / `waiting`) and `version`. That tells us which sessions are outdated and which are idle.
- **`~/.claude/projects/*/<sessionId>.jsonl`**: the transcript. Its `ai-title` / `custom-title` records hold the session title, which Orca shows as the tab title. That links a session to a tab. Assistant records carry `requestedModel` and `effort`; the output of `/model` and `/effort` is also recorded (`Set model to \`Opus 5.5\` … \`max\` effort …`). The latest of these is the model and effort the session is really using.
- **Orca CLI** (`orca terminal list|read --screen|send`): lists tabs (with `agentIdentity: "claude"` and `title`), reads the rendered screen, and types into a tab.

### 3. Mistakes found while testing on real tabs

Each of these was hit on a live tab and then fixed. They are the reason the script looks the way it does:

1. **The process got renamed.** After an update, the running binary becomes `claude.exe.old.<n>`, so a check for process name `claude` matched nothing. The script now matches the `claude*` prefix.
2. **"Trust this folder?" defaults to *No, exit*.** Resuming a session in the home folder shows the trust prompt again. A blind Enter would quit. The script presses ↓, checks that the cursor is on *Yes*, then presses Enter.
3. **A plain `--resume` silently resets model and effort.** In the first test, a tab running *Sonnet 5.5 / high* came back as *Opus* (the settings default), and a tab on *max* effort came back on *high*. Now the script reads both from the transcript, passes `--model` and `--effort`, and checks the effort shown on screen afterwards. (`/model` was deliberately not used to repair things, because it also changes your global default.)
4. **An unsent feedback draft blocks `/exit`.** Claude Code asks whether to send or discard it. Choosing for the user is not acceptable, so such tabs are detected beforehand (status line shows `feedback draft`) and skipped.
5. **`orca terminal wait --for tui-idle` timed out on idle Claude tabs**, so idleness comes from Claude Code's own `status` field instead.

### Limitations

- Windows only (paths and the `.exe` assumptions). PRs for macOS/Linux welcome.
- Tested with the native installer (`~/.local/bin/claude.exe`), on PowerShell 5.1 and 7. npm installs (session process is `node`) are accepted but **not tested**.
- It reads Claude Code's English UI text ("Yes, I trust this folder", "feedback draft", "· /effort"). Claude Code's terminal UI is English regardless of your Windows language, so the Windows language does not matter. It was developed on a Korean Windows.
- Relies on undocumented Claude Code files (`sessions/*.json`, transcript record shapes). A future version may change them. The script then skips instead of guessing.
- Model names are mapped from display names like `Opus 5.5` → `claude-opus-5-5`. Anything else (for example 1M-context variants set via `/model`) is skipped.
- Tabs are matched by title. Two tabs with identical titles are skipped.
- Session-only settings other than model and effort are not carried over.

## License

MIT

---

## 한국어

Orca 탭 여러 개에서 Claude Code를 쓰다 보면, Claude Code가 업데이트될 때마다 탭마다 `✔ Update installed · Restart to update`가 뜹니다. 없애려면 탭을 하나하나 `/exit` → `claude --resume` 해야 합니다. 이 스크립트는 **더블클릭 한 번으로 전부** 처리합니다. 대화, 모델, 노력 수준은 그대로 유지됩니다.

- 미리보기: `powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1 -DryRun`
- 실행: `powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1`
- 윈도우 기본 PowerShell 5.1과 PowerShell 7 모두 됩니다. 윈도우 언어(한글·영어)는 상관없습니다.
- 작업 중인 탭, 입력창에 쓰던 글이 있는 탭, 보내지 않은 피드백 초안이 있는 탭, 이미 최신인 탭은 건드리지 않습니다.
- 만든 과정과 시험하면서 실제로 겪은 실수 5가지는 위 **How it works** 절에 있습니다. Claude Code(Opus 5.5)가 Orca 안에서 한 세션 만에 만들고, 실제 탭에서 시험했습니다.
