Selenium Grid Deployer – Requirements

1. Functional Requirements
   • Hub Deployment
   • Windows Host PC는 Selenium Hub 역할을 한다.
   • Hub는 Windows 서비스(NSSM) 로 등록되어야 하며:
   • PC 시작 시 자동 실행
   • 예기치 않은 종료 시 자동 재시작
   • Hub는 Grid 상태와 세션을 관리하고, 클라이언트 요청을 Node로 라우팅해야 한다.
   • Node Deployment
   • VM 한 대 = Selenium Node 한 개로 매핑되어야 한다.
   • Node는 Microsoft Edge 브라우저와 대응되는 Edge WebDriver를 포함해야 한다.
   • Node는 VM 시작과 동시에 Autologon → Scheduled Task를 통해 자동 실행되어야 한다.
   • Node는 예기치 않은 종료 시 Watchdog 스크립트에 의해 자동으로 재시작되어야 한다.
   • Node는 Hub에 자동 등록되어야 하며, 세션 타임아웃 후 정리 기능을 지원해야 한다.
   • Scaling
   • 하나의 Base VHDX 이미지를 기반으로 여러 Node VM을 자동으로 생성할 수 있어야 한다.
   • deploy_selenium_node.ps1 스크립트는 파라미터(Name, BaseVhdx, SwitchName, HubIp, etc.)를 받아 노드 배포를 단순화해야 한다.

⸻

2. Non-Functional Requirements
   • Idempotency
   • 스크립트는 여러 번 실행해도 안전해야 한다. (중복 생성 시 에러 없이 확인 가능)
   • Reproducibility
   • Packer를 사용하여 Base VHDX를 재현 가능하게 빌드할 수 있어야 한다.
   • Self-Healing
   • Hub/Node 모두 예기치 않은 크래시에서 자동으로 복구해야 한다.
   • Maintainability
   • 스크립트와 문서는 사람이 직접 실행하거나 AI Agent(Codex, Claude Code 등)가 파싱/실행하기 쉽게 작성되어야 한다.
   • Observability
   • Hub 상태와 Node 등록 현황을 API(GET /status) 또는 UI(http://<hub>:4444/ui)로 확인할 수 있어야 한다.

⸻

3. Constraints
   • OS / Platform
   • Host: Windows 10/11 Pro 이상 (Hyper-V 지원 필수)
   • Node: Windows VM (Edge 실행 가능 환경)
   • Software Stack
   • Java 17 JRE
   • Selenium Server (Hub/Node 동일 버전)
   • Microsoft Edge (Stable channel) + Edge WebDriver (동일 메이저 버전)
   • Language
   • PowerShell (Host 스크립트)
   • Packer HCL (이미지 빌드 자동화)
   • Security
   • Autologon 계정은 최소 권한 사용자여야 하며, 네트워크 상에서 격리되어야 한다.
