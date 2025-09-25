packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = ">= 1.0.0"
    }
  }
}

variable "iso_url" {
  type        = string
  description = "Path or URL to Windows installation ISO"
}

variable "iso_checksum" {
  type        = string
  description = "Checksum for the Windows ISO (e.g. sha256:<hash>)"
}

variable "host_switch" {
  type        = string
  default     = "Default Switch"
  description = "Hyper-V virtual switch used for the build VM"
}

variable "build_cpus" {
  type        = number
  default     = 4
  description = "vCPU count for the build VM"
}

variable "build_mem_mb" {
  type        = number
  default     = 4096
  description = "Memory (MB) for the build VM"
}

variable "disk_size" {
  type        = number
  default     = 51200
  description = "Primary disk size for the VM (MB)"
}

variable "selenium_version" {
  type        = string
  default     = "4.23.0"
  description = "Selenium Server version bundled inside the image"
}

variable "hub_ip" {
  type        = string
  default     = "192.168.0.10"
  description = "Hub IP address nodes will register against"
}

variable "grid_user" {
  type        = string
  default     = "griduser"
  description = "Least privilege autologon account"
}

variable "grid_pass" {
  type        = string
  sensitive   = true
  description = "Password for the autologon account"
}

variable "admin_pass" {
  type        = string
  sensitive   = true
  description = "Temporary Administrator password during build"
}

variable "edge_channel" {
  type        = string
  default     = "Stable"
  description = "Edge channel to install (used by install.ps1)"
}

locals {
  artifact_name = "incon-selenium-node-base"
}

source "hyperv-iso" "win" {
  iso_url            = var.iso_url
  iso_checksum       = var.iso_checksum
  communicator       = "winrm"
  winrm_username     = "Administrator"
  winrm_password     = var.admin_pass
  winrm_timeout      = "6h"
  winrm_use_ssl      = false
  winrm_insecure     = true
  winrm_port         = 5985

  disk_size          = var.disk_size
  generation         = 2
  cpus               = var.build_cpus
  memory             = var.build_mem_mb
  switch_name        = var.host_switch
  vm_name            = "packer-${local.artifact_name}"
  enable_secure_boot = false
  enable_uefi        = true
  output_directory   = "output-${local.artifact_name}"
  temp_path          = "packer-temp"
  skip_output_cleanup = true
  floppy_files       = ["autounattend.xml"]

  shutdown_command = "C:\\Windows\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /shutdown /quiet /mode:vm"
  shutdown_timeout = "30m"
}

build {
  name    = local.artifact_name
  sources = ["source.hyperv-iso.win"]

  provisioner "file" {
    source      = "scripts/start-node.ps1"
    destination = "C:\\Windows\\Temp\\start-node.ps1"
  }

  provisioner "file" {
    source      = "scripts/watchdog.ps1"
    destination = "C:\\Windows\\Temp\\watchdog.ps1"
  }

  provisioner "powershell" {
    script = "scripts/install.ps1"
    environment_vars = [
      "PKR_SELENIUM_VERSION=${var.selenium_version}",
      "PKR_HUB_IP=${var.hub_ip}",
      "PKR_GRID_USER=${var.grid_user}",
      "PKR_GRID_PASS=${var.grid_pass}",
      "PKR_EDGE_CHANNEL=${var.edge_channel}"
    ]
  }

  post-processor "manifest" {
    output = "packer-manifest.json"
  }
}
