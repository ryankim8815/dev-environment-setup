# 설치 후 수동 작업

## 기본 도구와 셸

1. Command Line Tools가 없으면 `xcode-select --install`을 실행하고 Apple 설치 UI를 완료합니다.
2. Homebrew 설치 중 관리자 인증이 필요하면 터미널의 안내에 따릅니다. 전체 setup 스크립트를 sudo로 실행하지 않습니다.
3. 설치 후 새 터미널에서 `nvm --version`, `mamba --version`을 확인합니다. nvm은 Node를 선택하거나 설치하지 않습니다. mamba base는 자동 활성화하지 않습니다.
4. shell_init을 끈 경우 결과에 표시된 코드 중 필요한 부분만 직접 셸 설정에 추가합니다.

기존 nvm·mamba·Oh My Zsh를 업데이트할 때는 각 공식 문서의 방법을 사용하고 기존 Node 버전, Python 환경, 셸 커스텀 설정을 보존하세요. 자동화는 사용자 홈이나 도구 루트 전체를 삭제하지 않습니다.

## Git과 로그인

Git의 이름·이메일은 사용자가 직접 설정합니다. 공개 config에는 넣지 마세요.

```bash
git config --global user.name '<사용할 이름>'
git config --global user.email '<사용할 이메일>'
git config --global credential.helper osxkeychain
```

GitHub CLI, IDE, AI 앱은 설치 후 직접 실행해 로그인합니다. 패키지는 로그인 세션·토큰·설정을 가져오지 않습니다. `gh auth login`이나 AI 도구의 로그인 명령도 자동으로 실행하지 않습니다.

## 앱별 작업

- Docker Desktop: 앱을 직접 실행하여 이용 조건·필수 권한·리소스를 설정합니다. 기존 Docker 데이터는 스크립트가 이동·삭제하지 않습니다.
- Orca: [공식 안내](https://www.onorca.dev/docs/install)를 참고합니다. 첫 실행의 개인 설정 가져오기는 별도의 사용자 선택입니다. 기존 `/Applications/Orca.app`은 자동으로 대체하지 않습니다.
- CuaDriver: [공식 안내](https://cua.ai/docs/how-to-guides/driver/install)에 따라 필요한 경우에만 앱 실행·접근성·화면 기록 권한을 설정합니다. 패키지는 데몬·스킬·MCP를 구성하지 않습니다. CLI 연결이 필요하면 공식 문서를 따르세요.
- Hermes: [공식 데스크톱 다운로드](https://hermes-agent.nousresearch.com/)를 사용합니다. CLI 설치 프로그램은 Python·uv·추가 환경을 구성할 수 있으므로 이 패키지에서는 자동 실행하지 않습니다. 원하는 mamba 기반 구성과 충돌하지 않는지 설치 옵션을 확인하세요.
- Ollama: 필요할 때 직접 서버를 시작하고 모델을 선택하여 다운로드합니다.
- IDE 확장: 확장 ID는 `publisher.extension` 형식으로 config에 입력하고 해당 IDE도 활성화합니다. 사설 마켓플레이스 인증은 직접 설정합니다.

자동 설치 실패 시 결과의 공식 링크와 로컬 diagnostics.log를 확인하세요. 실행 경로에 수동 설치가 먼저 잡혀 있으면 경로·설치 출처를 정리한 후 재실행합니다. 스크립트가 임의로 기존 바이너리를 삭제하거나 링크를 덮어쓰지는 않습니다.

## Kubernetes

kubectl·Krew가 없는 경우 cnpg의 차단 사유에 표시되는 config 키를 활성화하세요. 단순히 비활성화된 기존 도구는 사용할 수 있으므로 다시 설치할 필요가 없습니다.

클러스터 연결 설정은 별도 작업입니다. 이 패키지에 kubeconfig·클러스터 주소·인증서·토큰을 넣지 마세요. setup의 검사 성공은 로컬 도구 설치 확인이며 클러스터 연결·서버 버전 호환성 검증을 뜻하지 않습니다.

## 로그와 백업

실행 기록은 홈 아래 `Library/Application Support/dev-environment-setup/runs`에 있습니다. 변경 전 zshrc 및 직접 관리하는 앱·바이너리의 교체 전 백업을 같은 실행 폴더에서 확인할 수 있습니다. 원본을 확인한 후 필요한 파일만 직접 복원하세요. 다른 실행의 백업을 자동으로 덮어 적용하지 않습니다.

이 폴더와 개인 config를 공개 저장소에 복사하지 마세요. 문제 보고에는 인증정보·개인 경로를 제거한 오류 요약만 공유하세요.
