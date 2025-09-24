# Selenium Grid Deployer

📌 Overview

selenium-grid-deployer 는 Windows + Hyper-V 환경에서 Selenium Grid 전체(Hub + Node VM) 를 자동 배포하는 스크립트 모음입니다.
• Hub Deployer: Selenium Hub를 Windows 서비스(NSSM)로 설치
• Node Deployer: Base VHDX를 기반으로 VM(Node)을 차등 복제 후 자동 시작
• Packer Templates: Base VHDX를 재현성 있게 빌드

⸻

🚀 Features
• Hub 자동 배포: Java + Selenium Server Hub를 서비스로 등록, 부팅 시 자동 실행/재시작
• Node VM 배포: deploy_selenium_node.ps1 한 번으로 VM 생성 + Grid 등록
• Self-healing: Scheduled Task로 Node 프로세스/Edge 드라이버 죽었을 때 자동 재실행
• 재현성 보장: Packer로 Golden Image(Base VHDX) 빌드
• 확장성: 파라미터만 바꾸면 Node 수를 즉시 늘릴 수 있음

⸻

🗂️ Repository Structure

selenium-grid-deployer/
├─ docs/
│ ├─ requirements.md # 사람이 읽기 좋은 서술형 요구사항 문서
│ └─ requirements-checklist.yaml # AI Agent 친화적인 구조화 체크리스트
├─ hub/
│ └─ deploy_seleinum_hub.ps1 # Hub 설치/서비스 등록
├─ node/
│ ├─ deploy_selenium_node.ps1 # Node VM 생성 스크립트
│ └─ docs/node-deployer.md # Node Deployer 문서
├─ packer/
│ ├─ packer.pkr.hcl # Hyper-V용 Packer 템플릿
│ ├─ autounattend.xml # Windows 무인설치 응답파일
│ └─ scripts/ # install/start-node/watchdog
└─ README.md

⸻

⚙️ Prerequisites
• Windows 10/11 Pro (Hyper-V 활성화)
• PowerShell (관리자 권한)
• Java 17 JRE (자동 설치 지원)
• Packer (선택, Base VHDX 빌드용)

⸻

🛠️ Usage

1. Build Base VHDX (선택)

```
cd packer
packer init .
packer build `
  -var iso_url="file:///D:/ISO/Win11.iso" `
  -var iso_checksum="sha256:<HASH>" `
  -var hub_ip="192.168.0.10" `
  -var grid_pass=$ENV:GRID_PASS `
  -var admin_pass=$ENV:ADMIN_PASS `
  .
```

2. Deploy Hub

```
cd hub
.\deploy_hub.ps1 -SeleniumVersion "4.23.0" -Port 4444
```

    •	Hub는 Windows 서비스로 등록되어, PC 부팅 시 자동 시작
    •	Hub UI: http://<HOST_IP>:4444/ui

3. Deploy Node VM

```
cd node
.\deploy_selenium_node.ps1 `
  -Name "SeleniumNode01" `
  -BaseVhdx "D:\VMs\base.vhdx" `
  -SwitchName "Default Switch" `
  -HubIp "192.168.0.10"
```

4. Scale-out Multiple Nodes

```
1..2 | ForEach-Object {
  .\deploy_selenium_node.ps1 `
    -Name "SeleniumNode0$_" `
    -BaseVhdx "D:\VMs\base.vhdx" `
    -SwitchName "Default Switch" `
    -HubIp "192.168.0.10"
}
```

⸻

🔍 Health Check
• Hub Console: http://<HOST_IP>:4444/ui
• Hub Status API: GET http://<HOST_IP>:4444/status
• Node 자동 등록 확인 가능

⸻

📜 License
MIT
