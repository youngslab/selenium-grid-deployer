Packer Guide (Hyper-V / Windows)

이 문서는 Windows + Hyper-V 환경에서 Selenium Node용 Golden Image(Base VHDX) 를 재현성 있게 빌드하기 위한 Packer 사용 방법을 단계별로 안내합니다.
생성된 Base VHDX는 node/deploy_selenium_node.ps1 스크립트로 Node VM을 빠르게 확장(스케일-아웃)하는 데 사용됩니다.

⸻

1. 개요
   • 목표: VM 한 대 = Selenium Node 한 개. Node가 Autologon → Scheduled Task로 Selenium Node를 자동 실행하고, Hub에 자동 등록되도록 하는 Base VHDX 생성
   • 이미지에 포함:
   • Autologon(최소 권한 사용자)
   • Java 17 JRE
   • Microsoft Edge (Stable) + Edge WebDriver (동일 메이저)
   • Selenium Server JAR (버전 고정)
   • start-node.ps1, watchdog.ps1 + 작업 스케줄러 3종(OnLogon/Watchdog/OnStart Clean)
   • 절전/화면잠금 비활성화(테스트 중 화면 UI 필요)
   • 빌더: hyperv-iso
   • 프로비저너: PowerShell

⸻

2. 디렉터리 구조

selenium-grid-deployer/
└─ packer/
├─ packer.pkr.hcl # 메인 템플릿
├─ autounattend.xml # Windows 무인설치 응답 파일
├─ scripts/
│ ├─ install.ps1 # VM 내부: 필수 SW 설치, 스크립트/스케줄러 등록
│ ├─ start-node.ps1 # VM 내부: 노드 시작 스크립트(로그온 시)
│ ├─ watchdog.ps1 # VM 내부: 좀비/충돌 복구
│ └─ post_build_host.ps1 # (선택) Host: Hub 서비스 설치 + Node VM 다중 생성
└─ docs/
└─ packer.md # (본 문서)

⸻

3. 요구사항(Host)
   • Windows 10/11 Pro 이상 (Hyper-V 기능 활성화)
   • 관리자 권한 PowerShell
   • 디스크 여유 공간(ISO + VHDX)
   • (선택) 인터넷 접속(winget/choco/selenium JAR 다운로드용)

Hyper-V 활성화 예시:

Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart

⸻

4. 변수/비밀 관리

민감 값(예: Autologon 비밀번호)은 환경 변수 또는 Packer var-file로 주입하세요.
레포에는 평문으로 커밋하지 않는 것을 권장드립니다.
• 환경 변수 예:
• ADMIN_PASS (설치 중 Administrator 암호)
• GRID_PASS (Autologon 사용자 암호)
• var-file 예: secrets.pkrvars.hcl (Git에 미추적)

admin_pass = "AdminTemp!ChangeMe"
grid_pass = "GridUser!ChangeMe"
hub_ip = "192.168.0.10"

⸻

5. 핵심 파일 설명

5.1 packer.pkr.hcl (요약)
• ISO 경로/해시, Hyper-V 스위치, CPU/메모리, WinRM 접속 정보 등
• scripts/install.ps1를 호출하여 VM 내부 구성

packer {
required_plugins {
hyperv = { source = "github.com/hashicorp/hyperv", version = ">= 1.0.0" }
}
}

variable "iso_url" { type = string }
variable "iso_checksum" { type = string }
variable "host_switch" { type = string default = "Default Switch" }
variable "build_cpus" { type = number default = 4 }
variable "build_mem_mb" { type = number default = 4096 }
variable "selenium_version" { type = string default = "4.23.0" }
variable "hub_ip" { type = string default = "192.168.0.10" }
variable "grid_user" { type = string default = "griduser" }
variable "grid_pass" { type = string sensitive = true }
variable "admin_pass" { type = string sensitive = true }

source "hyperv-iso" "win" {
iso_url = var.iso_url
iso_checksum = var.iso_checksum
communicator = "winrm"
winrm_username = "Administrator"
winrm_password = var.admin_pass
winrm_timeout = "6h"

shutdown_command = "C:\\Windows\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /shutdown /quiet /mode:vm"
cpus = var.build_cpus
memory = var.build_mem_mb
generation = 2
switch_name = var.host_switch
floppy_files = ["autounattend.xml"]
}

build {
name = "incon-selenium-node-base"
sources = ["source.hyperv-iso.win"]

provisioner "powershell" {
script = "scripts/install.ps1"
environment_vars = [
"PKR_SELENIUM_VERSION=${var.selenium_version}",
"PKR_HUB_IP=${var.hub_ip}",
"PKR_GRID_USER=${var.grid_user}",
"PKR_GRID_PASS=${var.grid_pass}"
]
}
}

5.2 autounattend.xml (요약)
• 무인 설치, WinRM 활성화, 로캘/라이선스 동의, 임시 Administrator 암호 설정
• 조직 표준에 맞게 커스터마이즈 가능

5.3 scripts/install.ps1 (핵심 로직)
• choco/winget 설치 → temurin17jre, Edge, Edge WebDriver
• C:\selenium 폴더 생성 + Selenium JAR 다운로드(버전 고정)
• Autologon 사용자 생성 + 레지스트리 Autologon (운영에선 Sysinternals Autologon 권장)
• start-node.ps1, watchdog.ps1 생성
• Task Scheduler 3종 등록(OnLogon/Watchdog/OnStart Clean)
• 절전/화면잠금 비활성화

설치 스크립트는 README/캔버스에 제공된 예시와 동일 구조를 사용합니다.

⸻

6. 빌드 절차

6.1 Packer 준비

cd selenium-grid-deployer\packer
packer init .

6.2 빌드 실행 (환경변수 방식)

$env:ADMIN_PASS="AdminTemp!ChangeMe"
$env:GRID_PASS="GridUser!ChangeMe"

packer build `  -var iso_url="file:///D:/ISO/Win11.iso"`
-var iso_checksum="sha256:<YOUR_ISO_SHA256>" `  -var hub_ip="192.168.0.10"`
-var admin_pass="$env:ADMIN_PASS" `
  -var grid_pass="$env:GRID_PASS" `
.

6.3 빌드 실행 (var-file 방식)

packer build -var-file="secrets.pkrvars.hcl" -var "iso_url=file:///D:/ISO/Win11.iso" -var "iso_checksum=sha256:<HASH>" .

6.4 산출물 확인
• Packer 콘솔 출력에 VHDX 경로가 표시됩니다.
• 보통 hyperv 빌더의 아웃풋 디렉터리 하위에 생성됩니다.
• 해당 Base VHDX를 node/deploy_selenium_node.ps1에서 부모 디스크로 참조하여 차등 디스크 VM을 생성합니다.

⸻

7. Base VHDX 소비(노드 배포)

7.1 단일 노드

cd ..\node
.\deploy_selenium_node.ps1 `  -Name "SeleniumNode01"`
-BaseVhdx "D:\VMs\incon-selenium-node-base.vhdx" `  -SwitchName "Default Switch"`
-HubIp "192.168.0.10"

7.2 다중 노드

1..2 | % {
.\deploy*selenium_node.ps1 `
-Name "SeleniumNode0$*" `    -BaseVhdx "D:\VMs\incon-selenium-node-base.vhdx"`
-SwitchName "Default Switch" `
-HubIp "192.168.0.10"
}

⸻

8. 버전 고정 전략
   • Selenium Server: selenium_version 변수로 고정
   • Edge/Driver: Stable 채널 사용 + 설치 시 동기화
   • 필요 시 start-node.ps1에서 버전 비교 경고를 남기는 스니펫 추가
   • 주기적 재빌드: 월 1회 또는 업데이트 필요 시 Packer 재실행

⸻

9. 검증/헬스체크
   • Hub UI: http://<HOST_IP>:4444/ui
   • Hub Status API: GET http://<HOST_IP>:4444/status
   • Node 자동 등록 확인

⸻

10. 보안 권고
    • Autologon 계정은 최소 권한으로 생성
    • 레지스트리 Autologon 대신 Sysinternals Autologon 사용 권장
    • Hub/Node 네트워크 세그먼트 격리, 방화벽 예외 최소화
    • 비밀번호/토큰 등 비밀 값은 var-file(.gitignore) 또는 환경 변수로 전달

⸻

11. 트러블슈팅

증상 원인 해결
Packer가 WinRM 접속 실패 autounattend 설정/네트워크 문제 autounattend.xml WinRM 설정 확인, vSwitch/DHCP 확인
빌드 중 Edge/Driver 설치 실패 Winget 연결/소스 이슈 재시도, 프록시 환경 설정, 오프라인 패키지 사용 검토
Node가 Hub에 미등록 Hub 주소/포트 오류, 스크립트 미실행 start-node.ps1의 $hub 확인, Scheduled Task 로그 점검
Edge/Driver 버전 불일치 업데이트 타이밍 차이 Winget 강제 업데이트, 버전 고정/검증 스니펫 추가
부팅 후 화면 잠김으로 자동실행 안됨 전원/잠금 정책 powercfg 및 잠금/스크린세이버 해제 재확인

⸻

12. CI 예시 (선택)

GitHub Actions에서 Packer validate 정도를 자동화할 수 있습니다.

name: packer-validate

on:
pull_request:
paths: - "packer/\*\*"

jobs:
validate:
runs-on: windows-latest
steps: - uses: actions/checkout@v4 - name: Install Packer
run: choco install -y packer - name: Packer Init
working-directory: ./packer
run: packer init . - name: Packer Validate
working-directory: ./packer
run: packer validate .

실제 build는 Runner 권한/환경 제약으로 로컬에서 수행하는 것을 권장드립니다.

⸻

13. FAQ

Q. 꼭 Packer가 필요할까요?
A. 수동으로도 가능하지만, 재현성/버전 고정/자동화를 위해 Packer를 권장합니다.

Q. VMware/VirtualBox로도 만들 수 있나요?
A. 가능합니다. 빌더만 교체하면 되고, 스크립트는 대부분 재사용됩니다. 추후 vmware-iso/virtualbox-iso용 템플릿을 추가할 수 있습니다.

Q. Autologon은 보안상 불안합니다.
A. 최소 권한 계정 사용, 네트워크 격리, Sysinternals Autologon 사용, 비밀 값 외부 주입 등으로 리스크를 완화하세요.

⸻

14. 체크리스트(요약)
    • Hyper-V 활성화
    • ISO/해시 준비
    • packer.pkr.hcl 변수 설정
    • autounattend.xml WinRM/로캘 검증
    • install.ps1 내 버전/스크립트 경로 확인
    • packer build 성공 → VHDX 산출
    • deploy_selenium_node.ps1로 Node VM 생성
    • Hub UI에서 Node 등록 확인

⸻

필요하시면 이 가이드를 한국어/영어 2가지 버전으로 분리해서 넣거나, 조직 표준에 맞춘 사내 Packer 베스트 프랙티스(캐싱, 미러링, 오프라인 설치 등) 섹션도 추가해 드리겠습니다.
