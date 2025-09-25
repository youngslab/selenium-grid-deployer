# Selenium Grid Deployer

Windows + Hyper-V 환경에서 Selenium Grid(Hub + Node VM)를 손쉽게 배포하기 위한 스크립트/템플릿 모음입니다. Base VHDX(골든 이미지)를 만들어 빠르게 Node VM을 증설하고, Hub는 서비스 형태로 운영하는 것을 목표로 합니다.

## 주요 기능
- Hub 자동 배포: Selenium Server Hub를 Windows 서비스로 등록하여 부팅 시 자동 실행(선택)
- Node VM 배포: 차등 디스크(Base VHDX) 기반으로 Hyper-V VM을 신속히 생성 및 Grid 등록
- Self-healing: 스케줄러/워치독으로 Node 프로세스/드라이버 비정상 종료 시 자동 복구(설계)
- 재현성 확보: Packer 템플릿으로 Golden Image(Base VHDX) 일관 빌드
- 파라미터 기반 구성: 이름/리소스/스위치/Hub IP 등 유연한 설정

## 리포지토리 구조
```
selenium-grid-deployer/
├─ README.md
├─ docs/
│  ├─ requirements.md                 # 요구사항 정리
│  └─ requirements-checklist.yaml     # 체크리스트(자동화 친화)
├─ node/
│  └─ docs/
│     └─ node_deployer.md             # Node 배포 문서 및 예제 스크립트
└─ packer/
   ├─ packer.pkr.hcl                  # Hyper-V용 Packer 템플릿
   ├─ autounattend.xml                # Windows 무인 설치 응답 파일
   ├─ docs/
   │  └─ packer.md                    # Packer 상세 가이드
   └─ scripts/                        # VM 내부에서 실행될 스크립트들
      ├─ install.ps1
      ├─ start-node.ps1
      └─ watchdog.ps1
```

## 선행 조건(Prerequisites)
- Windows 10/11 Pro 이상(Hyper-V 기능 활성화)
- 관리자 권한 PowerShell
- Java 17 JRE(Hub 실행 시 필요)
- Packer(선택, Base VHDX 빌드 시)

## 사용법(Usage)

1) Base VHDX 빌드(선택)
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

2) Hub 배포
- 스크립트 방식(추가 예정) 또는 수동 실행 중 선택합니다.
- 수동 실행 예시:
```
java -jar selenium-server-4.23.0.jar hub --port 4444
```
- 서비스(상시 실행)로 운영하려면 NSSM 등으로 등록하는 방법을 권장합니다.

3) Node VM 배포
- Node 배포 스크립트와 파라미터 예시는 `node/docs/node_deployer.md`를 참고하세요.
- 예시(가정):
```
cd node
./deploy_selenium_node.ps1 `
  -Name "SeleniumNode01" `
  -BaseVhdx "D:\\VMs\\base.vhdx" `
  -SwitchName "Default Switch" `
  -HubIp "192.168.0.10"
```

4) 다중 노드 스케일 아웃 예시(가정)
```
1..2 | ForEach-Object {
  ./deploy_selenium_node.ps1 `
    -Name "SeleniumNode0$_" `
    -BaseVhdx "D:\\VMs\\base.vhdx" `
    -SwitchName "Default Switch" `
    -HubIp "192.168.0.10"
}
```

## 상태 점검(Health Check)
- Hub UI: http://<HOST_IP>:4444/ui
- Hub Status API: GET http://<HOST_IP>:4444/status
- Node가 Hub에 정상 등록되었는지 확인

## 라이선스
MIT

