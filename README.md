# Apple Silicon Mac 개발환경 자동 세팅

새 Mac과 일부 도구가 설치된 Mac에 **선택한 도구와 범용 설정**을 구성합니다. 미설치 도구는 실행 시점의 최신 안정 버전으로 설치하고, 기존 버전은 기본적으로 유지합니다.

macOS 기본 Bash 3.2와 JXA를 사용합니다. 스크립트 실행을 위해 Node.js, Python, jq를 설치할 필요가 없습니다. Apple Silicon의 네이티브 터미널에서 일반 사용자로 실행하세요. 전체 스크립트를 `sudo`로 실행하지 마세요.

## 사용 방법

```bash
cp config.example.json config.local.json
# config.local.json에서 필요한 tools 항목의 enabled를 수정합니다.
bash setup.sh --config config.local.json --dry-run
bash setup.sh --config config.local.json
bash setup.sh --config config.local.json --check
```

폴더 전체를 다른 Mac에 옮겨 같은 방식으로 실행할 수 있습니다. 설치 경로와 홈은 실행 시 계산합니다. 개인 설정이나 현재 컴퓨터의 설치 목록을 자동으로 추출하지 않습니다.

| 명령 | 동작 |
|---|---|
| `bash setup.sh` | 로컬 config가 있으면 사용하고, 없으면 공개 예제 사용 |
| `--config FILE` | 다른 JSON 설정 파일 선택 |
| `--dry-run` | 설치·설정 변경 없이 예정 작업, 버전 차이, 차단 사유 표시 |
| `--check` | 로컬 설치·버전·실행 경로·셸 초기화 확인 |
| `--help` | 사용법 표시 |

검사 모드도 공식 릴리스·패키지 메타데이터를 조회하므로 인터넷 연결이 필요합니다. 임시 메타데이터는 실행 후 제거합니다. 클러스터 API에는 접속하지 않습니다. `--dry-run` 결과가 적용 시점까지 버전을 고정하지는 않습니다.

종료 코드: `0` 완료 또는 정책에 따른 기존 버전 유지, `1` 실패·차단·수동 작업·미완료 검사, `2` config 또는 실행 환경 오류입니다. 오래된 버전을 유지하도록 설정한 경우에는 차이를 표시하되 오류로 처리하지 않습니다.

## 설치 목록

전체 도구 ID와 기본값은 `config.example.json`, 설치 경로와 공식 링크는 `lib/catalog.tsv`에 있습니다. 누락한 도구는 비활성화합니다.

| 그룹 | 도구 | 기본값 |
|---|---|---|
| 기본 도구 | Xcode Command Line Tools, Homebrew, Git, GitHub CLI, Oh My Zsh | 켬 |
| Node.js 관리 | nvm | 켬 |
| Python 관리 | Miniforge 기반 mamba | 켬 |
| 개발 앱 | VS Code, Cursor, Kiro, DBeaver, Postman, Redis Insight | 끔 |
| AI 도구 | ChatGPT, Codex 앱·CLI, Claude 앱·Code, Gemini CLI, OpenCode, Kiro CLI, Ollama, Hermes, Orca, CuaDriver | 끔 |
| Kubernetes | 아래 여섯 도구 | 끔 |
| 컨테이너 | Docker Desktop | 끔 |
| 인프라 코드 관리 | Terraform | 끔 |
| 로그·관측성 | LogCLI | 끔 |
| IDE 확장 | VS Code·Cursor·Kiro의 명시한 확장 | 빈 목록 |

앱과 CLI는 별도로 선택합니다. 예를 들어 `codex`는 데스크톱 앱, `codex_cli`는 CLI입니다. `claude`는 데스크톱 앱, `claude_code`는 코딩 CLI입니다. `ollama`는 CLI만 설치하며 서비스 시작이나 모델 다운로드를 하지 않습니다.

### Kubernetes

| config ID | 도구 | 역할 |
|---|---|---|
| `kubectl` | [kubectl](https://kubernetes.io/docs/reference/kubectl/) | 클러스터 리소스 조회·관리 |
| `helm` | [Helm](https://helm.sh/docs/) | 차트 기반 애플리케이션 배포 |
| `k9s` | [K9s](https://k9scli.io/) | 터미널 리소스·로그·상태 탐색 |
| `krew` | [Krew](https://krew.sigs.k8s.io/docs/user-guide/setup/install/) | kubectl 플러그인 관리 |
| `cnpg` | [cnpg](https://cloudnative-pg.io/docs/1.28/kubectl-plugin/) | CloudNativePG 운영 |
| `ncp_iam_authenticator` | [ncp-iam-authenticator](https://github.com/NaverCloudPlatform/ncp-iam-authenticator) | NCP IAM 기반 인증 |

모두 기본 비활성화이며 실행 결과에서도 **Kubernetes** 그룹으로 표시합니다. Docker·Terraform·LogCLI는 별도 그룹입니다.

cnpg는 Krew로만 설치합니다. 필요한 kubectl·Krew가 설치되어 있으면 비활성화 상태여도 재사용합니다. 없으면 활성화한 선행 도구를 먼저 설치합니다. 미설치·비활성화인 선행 도구는 자동으로 켜지 않고 설정 키와 차단 사유를 안내합니다. Krew에는 Git도 필요합니다.

```json
{
  "schema_version": 1,
  "tools": {
    "kubectl": { "enabled": true },
    "krew": { "enabled": true },
    "cnpg": { "enabled": true }
  }
}
```

이 예시는 이미 설치된 Homebrew·Git을 이용합니다. 없는 기기에서는 필요한 기반 도구도 활성화하세요. cnpg의 최신 버전은 Krew 공식 인덱스를 기준으로 결정하며, 문서 URL의 버전으로 고정하지 않습니다. 플러그인 전체 업데이트는 하지 않습니다.

검증 명령은 `kubectl version --client`, Helm·K9s·Krew·cnpg·NCP 도구의 로컬 버전 명령뿐입니다. kubeconfig는 `/dev/null`로 격리합니다. 클러스터 조회·변경·로그 열람·인증 토큰 발급·K9s 대화형 실행은 하지 않습니다.

### 런타임 원칙

- nvm 관리 도구만 설치합니다. Node 버전, 기본 Node, npm 전역 패키지, Yarn은 설치하지 않습니다. 초기화에도 `--no-use`를 사용합니다.
- Python은 Miniforge의 mamba로 관리합니다. 관리용 base는 설치하지만 자동 활성화하지 않고 개발 환경도 만들지 않습니다.
- 별도 Python·uv·Go·Java·JMeter는 직접 설치하지 않습니다. 소스 빌드를 위해 Go·Java 등을 추가하지 않습니다.
- 선택한 앱에 필요한 내부 종속성은 표시합니다. 예를 들어 Gemini CLI의 Homebrew Node 의존성은 nvm 버전으로 등록되지 않습니다. 사용자 기본 Python을 바꿀 수 있는 의존성은 자동 처리하지 않습니다.

## Config와 버전 보존

지원 필드는 `schema_version`, `defaults`, `tools`, `settings`, `extensions`입니다. 알 수 없는 키·도구 ID, 잘못된 자료형과 확장 ID는 설치 전에 거부합니다. config를 셸 코드로 실행하지 않습니다.

```json
{
  "schema_version": 1,
  "defaults": { "reinstall_on_version_mismatch": false },
  "tools": {
    "helm": { "enabled": true },
    "k9s": { "enabled": true, "reinstall_on_version_mismatch": true }
  },
  "settings": { "shell_init": true },
  "extensions": { "vscode": [], "cursor": [], "kiro": [] }
}
```

도구별 재설치 값이 전역 값보다 우선합니다. 생략한 전역 값은 `false`입니다. 특정 버전 고정은 지원하지 않습니다.

| 상태 | 처리 |
|---|---|
| 비활성화 | 설치·업데이트·삭제하지 않음 |
| 활성화·미설치 | 최신 안정 버전 설치 |
| 목표 버전 일치 | 유지 |
| 버전 불일치·재설치 false | 기존 버전 유지, 차이 표시 |
| 버전 불일치·재설치 true | 지원되는 관리 경로에서만 프로그램 본체 교체 |
| 버전·출처 불명 | 자동 삭제 없이 수동 확인 |
| 최신 조회 실패 | 기존 설치 유지, 설치·교체 중단 |

재설치 허용은 무조건 삭제하라는 의미가 아닙니다. Homebrew 항목은 선택한 패키지만 업데이트하고, 직접 설치한 관리 대상 바이너리·앱은 검증된 배포물로 교체합니다. 수동 설치, 기존 nvm·Oh My Zsh·mamba 환경처럼 보존을 확실히 검증하기 어려운 교체는 공식 안내와 함께 수동 처리로 남깁니다.

Homebrew 설치는 자동 Homebrew 업데이트·설치된 의존 패키지 업그레이드·정리 작업을 억제합니다. 런타임 의존성을 재귀 검사하고, 기존 의존 패키지의 버전 변경이 필요하면 차단합니다. 해당 의존 도구를 먼저 명시적으로 업데이트한 뒤 재실행하세요. Homebrew 자체의 오래된 메타데이터가 목표 버전과 다르면 자동 변경하지 않고 설치를 실패로 보고합니다.

앱 자체의 자동 업데이트 설정은 변경하지 않습니다. 이 패키지의 기존 버전 유지 정책은 **스크립트가 수행하는 설치·교체**에 적용됩니다.

### 설치 경로별 처리

- 일반 앱·CLI: Homebrew core/cask. ARM64 bottle을 사용할 수 없으면 소스 빌드 대신 차단합니다.
- nvm·Oh My Zsh: 공식 소스 배포물을 새 디렉터리에 설치합니다. Oh My Zsh는 버전 릴리스 대신 공식 기본 브랜치의 커밋을 기준으로 표시합니다.
- mamba: 공식 Miniforge ARM64 설치 파일과 SHA-256을 검증합니다. 새 base에 mamba를 구성하며 기존 base에는 설치 프로그램을 덮어 실행하지 않습니다.
- Krew: 공식 ARM64 릴리스. NCP 인증 도구: 공식 ARM64 릴리스·체크섬, `$HOME/.local/bin`.
- Terraform: [HashiCorp 공식 ARM64 배포물](https://developer.hashicorp.com/terraform/install)과 체크섬, `$HOME/.local/bin`.
- Docker: Homebrew 메타데이터가 가리키는 공식 DMG에서 앱만 `$HOME/Applications`에 설치합니다. Homebrew의 kubectl 링크 추가 동작은 실행하지 않습니다.
- Orca·CuaDriver: 공식 ARM64 릴리스의 앱을 `$HOME/Applications`에 설치하며 체크섬·앱 식별자·서명·아키텍처·OS 요구사항을 검사합니다. 앱·데몬 실행, 권한 요청, 개인 설정 가져오기, 스킬 설치는 하지 않습니다.
- Hermes: 설치 프로그램이 런타임·환경·설정을 함께 구성하므로 공식 데스크톱 설치 안내를 수동 작업으로 제공합니다.

원격 설치 정의가 변경되어 제약을 검증할 수 없거나 체크섬을 확보할 수 없으면 자동 설치를 중단합니다. Xcode Command Line Tools는 Apple 설치 UI에서 완료해야 합니다. 기존 설치의 최신 여부는 시스템 소프트웨어 업데이트에서 직접 확인합니다.

## 설정과 공개 저장소

셸은 기존 파일을 백업하고 `.zshrc`의 전용 관리 구역에 범용 초기화를 추가합니다. 기존 Oh My Zsh가 이미 로드되어 있으면 다시 로드하거나 테마를 덮어쓰지 않습니다. 처음 구성할 때는 기본 테마와 Git 플러그인을 사용합니다. 자동 Oh My Zsh 업데이트는 새 관리 구역에서 비활성화합니다.

`shell_init: false`이면 초기화 코드를 안내만 합니다. 설정 파일이 심볼릭 링크이거나 관리 구역이 손상되어 있으면 보존하고 수동 적용을 안내합니다. 새로운 Anaconda·별도 Python·Go·Java 초기화는 추가하지 않으며 기존 사용자가 작성한 코드를 삭제하지도 않습니다.

Git 이름·이메일·인증을 변경하지 않습니다. IDE·AI 앱의 개인 설정, 키 바인딩, 스니펫, 모델 선택, 스킬·MCP·자동화를 가져오지 않습니다. IDE 확장은 사용자가 지정한 미설치 항목만 추가하고 기존 확장을 업데이트·제거하지 않습니다.

로그·백업·설치 영수증은 `$HOME/Library/Application Support/dev-environment-setup`에 보관합니다. 로그와 백업에는 로컬 경로나 기존 설정이 포함될 수 있으므로 공개 저장소에 올리지 마세요. 공개 결과 파일과 테스트 데이터에는 실제 사용자 정보나 인증정보를 넣지 않습니다. `config.local.json`, `config.*.local.json`, 로그는 Git에서 제외합니다.

kubeconfig·클러스터 주소·인증서·토큰, SSH 개인키, 로그인 정보, 대화 기록, 프로젝트, 기존 Python 환경, Docker 데이터, AI 모델 파일은 수집하거나 이전하지 않습니다.

## 실패와 재실행

기반 도구가 실패하면 의존 작업만 차단하고 독립 작업은 계속합니다. 결과에서 완료·유지·예정·차단·실패·수동작업·확인필요를 구분합니다. 실제 설치 상태를 다시 조사하므로 같은 config로 재실행할 수 있습니다. 사용자 데이터 보존이 불확실한 상태에서는 자동 정리·전체 삭제·재설치를 하지 않습니다.

설치 후 권한·로그인·수동 처리 방법은 [수동 작업 안내](docs/manual-steps.md)를 참고하세요.

## 개발 검증

```bash
bash tests/run.sh
```

macOS에서 Bash·Zsh 문법 검사, 실제 JXA config 검증, 임시 홈·명령 대역 기반 설치 정책 및 설정 검증을 실행합니다. 테스트는 실제 패키지 설치와 클러스터 접속을 수행하지 않습니다. 검증 범위와 새 Mac 실설치 여부는 [검증 기록](docs/validation.md)에 구분해 기록합니다.
