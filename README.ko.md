# orca-claude-restart-all (한국어)

[Orca](https://github.com/stablyai/orca) 탭들에서 돌고 있는 Claude Code 세션을, 새로 설치된 Claude Code 버전으로 **더블클릭 한 번에 전부** 재시작합니다. 탭마다 대화 내용, 모델, 노력 수준(effort)은 그대로 유지됩니다.

> 지금은 윈도우 전용입니다. 윈도우 기본 PowerShell 5.1과 PowerShell 7 모두 됩니다. 윈도우 언어(한글·영어)는 상관없습니다.
> 딱 한 가지 불편 때문에 만들었습니다: [stablyai/orca#10597](https://github.com/stablyai/orca/issues/10597)

[English README](README.md)

## 무엇이 불편했나

Claude Code는 뒤에서 스스로 업데이트합니다. 그러면 실행 중인 세션마다 이런 문구가 뜹니다.

```
✔ Update installed · Restart to update
```

Orca는 일부러 터미널을 백그라운드 프로그램(데몬)에 살려 둡니다. 그래서 Orca를 닫거나 업데이트해도 에이전트가 안 죽습니다. 좋은 기능이지만, 그 대신 **에이전트들이 새 Claude Code 버전으로 절대 바뀌지 않습니다.** 탭마다 들어가서 `/exit` 하고, 맞는 대화를 `claude --resume` 으로 직접 다시 띄워야 합니다. 탭이 6개만 넘어도 귀찮고, 실수하기 쉽습니다(다른 대화를 열거나, 모델이나 노력 수준이 바뀌는 등).

Orca에는 아직 "에이전트 전부 재시작" 기능이 없습니다([#10597](https://github.com/stablyai/orca/issues/10597)은 열려 있고, 에이전트 CLI 업데이트 요청 [#24958](https://github.com/stablyai/orca/issues/24958)은 "당장은 안 함"으로 닫혔습니다).

## 하는 일

Claude Code가 돌고 있는 Orca 탭마다 다음 순서로 처리합니다.

1. 그 탭에서 어떤 Claude Code 세션이 돌고 있는지 찾습니다.
2. 그 세션이 **지금** 쓰고 있는 모델과 노력 수준을 읽습니다.
3. 탭에 `/exit` 를 보내고, 예전 프로그램이 꺼질 때까지 기다립니다.
4. 같은 탭에서 `claude --resume <세션 ID> --model <모델> --effort <노력 수준>` 을 실행합니다.
5. "이 폴더를 신뢰합니까?" 질문이 뜨면 **Yes** 를 고릅니다. 홈 폴더에서는 이 질문이 다시 뜨는데, 기본 선택이 **No, exit** 라서 그냥 넘기면 꺼집니다.
6. 세션이 새 버전으로 다시 떴는지, 화면에 표시된 노력 수준이 원래와 같은지 확인합니다.

다음 경우에는 그 탭을 건드리지 않습니다.

| 상황 | 이유 |
|---|---|
| 에이전트가 작업 중이거나 질문에 대한 답을 기다리는 중 | 작업을 끊지 않습니다 |
| 입력창에 쓰다 만 글이 있음 | `/exit` 가 그 글 뒤에 붙어 버립니다 |
| 보내지 않은 피드백 초안이 있음 | `/exit` 가 "보낼지 / 버릴지" 질문에서 멈춥니다. 사용자가 고를 일입니다 |
| 이미 최신 버전 | 할 일이 없습니다 |
| 모델·노력 수준을 못 읽었거나, 탭을 하나로 특정하지 못함 | 추측해서 하느니 건너뜁니다 |

## 사용법

필요한 것: 윈도우, 실행 중인 Orca, `claude` 명령. PowerShell은 기본 `powershell`(5.1)이나 `pwsh`(7) 아무거나 됩니다.

```powershell
# 1) 미리보기. 아무것도 보내지 않고, 무엇을 할지만 보여 줍니다.
powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1 -DryRun

# 2) 실행
powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1

# 제목에 특정 글자가 들어간 탭만
powershell -ExecutionPolicy Bypass -File .\claude-restart-all.ps1 -Only "기능이름"
```

`-ExecutionPolicy Bypass` 는 이번 한 번 실행에만 적용됩니다. 윈도우는 인터넷에서 받은 서명 없는 스크립트를 기본으로 막기 때문에, 이 옵션이 없으면 *"디지털 서명되지 않았습니다(not digitally signed)"* 오류가 납니다. 아니면 `Unblock-File .\claude-restart-all.ps1` 을 한 번 실행해도 됩니다. 실행 전에 스크립트를 한 번 읽어 보세요(약 130줄).

결과 예시:

```
Installed Claude Code: 2.1.311

[done] Refactor billing module - 2.1.310 -> 2.1.311 · claude-opus-5-5 · max
[done] Write release notes - 2.1.310 -> 2.1.311 · claude-sonnet-5-5 · high
[skip] Fix login bug - busy (busy)
[skip] Translate docs - unsent feedback draft (handle it in the tab)

Restarted 2 session(s).
```

- `[done]` 재시작 완료, `[skip]` 건너뜀, `[check]` 다시 띄웠지만 확인이 필요함, `[fail]` 실패(탭을 직접 확인)
- 작업 중이라 건너뛴 탭은 나중에 한 번 더 실행하면 됩니다. 이미 바뀐 탭은 알아서 건너뜁니다.
- 화면 출력은 영어입니다(전 세계 사용자용).

### 바탕화면 아이콘 만들기 (더블클릭용)

스크립트가 있는 폴더에서 PowerShell로 한 번만 실행하세요.

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\Restart all Claude.lnk")
$s.TargetPath = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$s.Arguments  = "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$((Resolve-Path .\claude-restart-all.ps1).Path)`""
$s.Save()
```

`GetFolderPath('Desktop')` 는 윈도우가 한글이든 영어든, 원드라이브로 옮겨졌든 진짜 바탕화면 폴더를 찾아 줍니다. 아이콘 이름은 `"Restart all Claude.lnk"` 부분을 `"클로드 전부 재시작.lnk"` 처럼 바꿔도 됩니다.

## 어떻게 동작하나 (그리고 어떻게 만들었나)

**Claude Code(Opus 5.5)** 가 Orca 안에서, 탭을 하나하나 껐다 켜는 데 지친 사용자의 요청으로 한 세션 만에 만들었습니다. 아래 내용은 추측이 아니라 실제 PC(Orca 1.4.242, Claude Code 2.1.310 → 2.1.311, 윈도우 11)에서 잰 것입니다.

### 1. 그 문구는 누가 띄우나

"Update installed · Restart to update" 는 얼핏 Orca 알림처럼 보입니다. 두 프로그램 파일에서 이 문구를 직접 찾아보니, Claude Code 프로그램에는 있고 Orca(`app.asar`)에는 없었습니다. Orca 자체는 이미 자동 업데이트(1.4.238 → 1.4.242)됐고, 에이전트들은 Orca 터미널 데몬의 자식 프로그램이라 그대로 살아 있었습니다(`daemon-host-profiles\…\Orca.exe` → `pwsh` → `claude`). 그러니 재시작해야 할 것은 Orca가 아니라 **Claude Code** 입니다.

### 2. 필요한 재료 찾기

Orca 내부를 건드리지 않고 아래 세 가지로 해결했습니다.

- **`~/.claude/sessions/<pid>.json`**: Claude Code가 실행 중인 대화형 세션마다 하나씩 쓰는 파일입니다. `pid`, `sessionId`, `status`(`idle` 대기 / `busy` 작업 중 / `waiting` 질문 대기), `version` 이 들어 있습니다. 어떤 세션이 옛 버전이고 어떤 세션이 쉬고 있는지 알 수 있습니다.
- **`~/.claude/projects/*/<sessionId>.jsonl`**: 대화 기록입니다. `ai-title` / `custom-title` 기록에 세션 제목이 있고, Orca는 이걸 탭 제목으로 씁니다. 이걸로 세션과 탭을 짝지읍니다. 응답 기록에는 `requestedModel` 과 `effort` 가 있고, `/model`·`/effort` 를 친 결과도 남습니다(`Set model to \`Opus 5.5\` … \`max\` effort …`). 이 중 가장 마지막 값이 그 세션이 실제로 쓰는 모델과 노력 수준입니다.
- **Orca 명령줄 도구**(`orca terminal list|read --screen|send`): 탭 목록(`agentIdentity: "claude"`, `title` 포함)을 보고, 화면을 읽고, 탭에 글자를 입력합니다.

### 3. 실제 탭에서 시험하다 겪은 실수 5가지

모두 실제 탭에서 겪고 고친 것입니다. 스크립트가 지금 모양이 된 이유입니다.

1. **프로그램 이름이 바뀌어 있었습니다.** 업데이트 후 실행 중인 프로그램 파일 이름이 `claude.exe.old.<숫자>` 로 바뀌어서, 이름이 `claude` 인지 확인하는 코드가 아무것도 못 찾았습니다. 지금은 `claude` 로 시작하는지 봅니다.
2. **"이 폴더를 신뢰합니까?" 기본 선택이 *No, exit* 입니다.** 홈 폴더에서 세션을 다시 띄우면 이 질문이 다시 뜨고, 그냥 Enter를 누르면 꺼집니다. 스크립트는 ↓ 를 누르고, 커서가 *Yes* 에 있는지 확인한 뒤 Enter를 누릅니다.
3. **그냥 `--resume` 하면 모델과 노력 수준이 소리 없이 기본값으로 돌아갑니다.** 첫 시험에서 *Sonnet 5.5 / high* 로 돌던 탭이 *Opus*(설정 기본값)로 떴고, *max* 였던 탭은 *high* 로 떴습니다. 지금은 대화 기록에서 둘 다 읽어 `--model`·`--effort` 로 넘기고, 뜬 뒤 화면 표시로 한 번 더 확인합니다. (`/model` 은 전체 기본값까지 바꿔 버려서 복구에 쓰지 않았습니다.)
4. **보내지 않은 피드백 초안이 `/exit` 를 막습니다.** Claude Code가 보낼지 버릴지 묻습니다. 사용자 대신 고르면 안 되므로, 이런 탭은 미리 알아보고(상태 줄에 `feedback draft` 표시) 건너뜁니다.
5. **`orca terminal wait --for tui-idle` 은 쉬고 있는 Claude 탭에서도 시간 초과가 났습니다.** 그래서 쉬는지 여부는 Claude Code 자체의 `status` 값으로 판단합니다.

### 한계

- 윈도우 전용입니다(경로와 `.exe` 가정). macOS·리눅스 지원 PR 환영합니다.
- 기본 설치 방식(`~/.local/bin/claude.exe`)으로 PowerShell 5.1과 7에서 시험했습니다. npm 설치(세션 프로그램이 `node`)도 인식하지만 **시험하지 않았습니다.**
- Claude Code 화면의 영어 문구("Yes, I trust this folder", "feedback draft", "· /effort")를 읽습니다. Claude Code 터미널 화면은 윈도우 언어와 상관없이 영어이므로 윈도우 언어는 문제가 안 됩니다. 한국어 윈도우에서 개발했습니다.
- 공식 문서에 없는 Claude Code 파일(`sessions/*.json`, 대화 기록 형식)에 기대고 있습니다. 앞으로 버전에서 바뀔 수 있고, 그러면 스크립트는 추측하지 않고 건너뜁니다.
- 모델 이름은 `Opus 5.5` → `claude-opus-5-5` 같은 화면 이름에서 바꿉니다. 그 밖의 이름(예: `/model` 로 고른 1M 컨텍스트 모델)은 건너뜁니다.
- 탭은 제목으로 찾습니다. 제목이 똑같은 탭이 둘이면 건너뜁니다.
- 모델과 노력 수준 말고 그 세션에서만 바꾼 다른 설정은 넘어가지 않습니다.

## 라이선스

MIT
