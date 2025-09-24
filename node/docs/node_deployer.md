# Selenium Node Deployer

## 개요

Selenium Node Deployer 는 selenium-grid-deployer 레포지토리 내 제공되는 스크립트(deploy_selenium_node.ps1)로,
VM 한 대 = Selenium Node 한 개 형태로 자동 배포를 단순화해 줍니다.
• Hyper-V 기반 Windows 환경 지원
• 차등 디스크를 이용해 빠르게 VM 생성
• 베이스 이미지(Base VHDX)에 미리 설치된 Autologon/Edge/WebDriver/Node 스크립트 활용
• Hub IP를 지정하면 VM이 기동되자마자 Selenium Grid에 자동 등록

⸻

사전 준비 1. Base VHDX (Golden Image)
• Autologon 계정
• Microsoft Edge + Edge WebDriver
• Java 17 JRE
• start-node.ps1, watchdog.ps1 + Scheduled Tasks 등록
• (Packer 등으로 1회 빌드) 2. Host 환경
• Windows 10/11 Pro 이상 (Hyper-V 활성화 필요)
• PowerShell 관리자 권한
• Hub가 이미 selenium-grid-deployer의 Hub 설치 스크립트로 동작 중

⸻

스크립트: deploy_selenium_node.ps1

param(
[string]$Name = "SeleniumNode01",
  [string]$BaseVhdx,
[string]$SwitchName = "Default Switch",
  [string]$VmRoot = "D:\VMs",
[int]$Cpu = 2,
  [int]$MemoryMB = 4096,
[string]$HubIp = "192.168.0.10"
)

$ErrorActionPreference = "Stop"

# 차등 디스크 생성

$diffVhdx = Join-Path $VmRoot ("$Name.vhdx")
New-VHD -Path $diffVhdx -ParentPath $BaseVhdx -Differencing | Out-Null

# VM 생성 및 설정

New-VM -Name $Name -MemoryStartupBytes (${MemoryMB}MB) -Generation 2 -SwitchName $SwitchName | Out-Null
Set-VM -Name $Name -ProcessorCount $Cpu

Remove-VMHardDiskDrive -VMName $Name -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -ErrorAction SilentlyContinue
Add-VMHardDiskDrive -VMName $Name -Path $diffVhdx

Set-VM -Name $Name -AutomaticStartAction StartIfRunning -AutomaticStopAction Save

# VM 시작

Start-VM $Name

Write-Host "[$Name] VM created and started. Will register to Hub at $HubIp once autologon + scheduled task kicks in."

⸻

## 사용 예시

### 단일 Node 생성

.\deploy_selenium_node.ps1 `  -Name "SeleniumNode01"`
-BaseVhdx "D:\VMs\base.vhdx" `  -SwitchName "Default Switch"`
-HubIp "192.168.0.10"

### 여러 Node 생성

1..2 | ForEach-Object {
.\deploy*selenium_node.ps1 `
-Name "SeleniumNode0$*" `    -BaseVhdx "D:\VMs\base.vhdx"`
-SwitchName "Default Switch" `
-HubIp "192.168.0.10"
}

⸻

## 동작 방식

1. 지정된 Base VHDX를 부모로 하는 차등 디스크 생성
2. 새 VM 생성 및 CPU/메모리 설정 적용
3. VM 시작 → Autologon 계정 로그인 → Scheduled Task에 의해 Node 자동 실행
4. Node가 지정된 Hub IP로 연결되어 Grid에 등록됨

⸻

## 장점

• 명령 한 줄로 Node VM 자동 생성
• 테스트 환경 확장(스케일 아웃)이 매우 간단
• VM 내부 셋업을 건드릴 필요 없이 동일한 Base 이미지 재사용
• Hub와 연동 시 즉시 Grid에 반영

⸻

## 관련 기능

• Hub Deployer – Selenium Hub를 Windows 서비스로 배포
• Packer Templates – Base VHDX 이미지를 자동 빌드
