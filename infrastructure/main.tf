# Ubuntu Base Image
resource "libvirt_volume" "ubuntu_base" {
  # Name of the shared Ubuntu disk inside the libvirt storage pool.
  name = "monitor_k8s-ubuntu-26.04-base.qcow2"  #change (monitor_k8s)
  pool = "default" #libvirt storage pool 
  # Create the volume from content downloaded from the configured URL.
  create = {
    content = {
      url = var.ubuntu_image_url
    }
  }
}

# VM Disks
resource "libvirt_volume" "ubuntu_disk" {
  for_each = var.vms
  name     = "${each.key}.qcow2"
  pool     = "default"
  capacity = each.value.disk * 1024 * 1024 * 1024
  # Store the disk in QCOW2 format.
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}
# locals (consolidated variables) for cloud-init and bootstrap scripts
locals {
  control_plane_key = [for k, v in var.vms : k if v.role == "control-plane"][0]
  control_plane_ip  = var.vms[local.control_plane_key].ip
  bootstrap_scripts = {
    for name, vm in var.vms : name => templatefile("${path.module}/cloud-init/auto-bootstrap.sh.tftpl", {#change file name
      role           = vm.role
      hostname       = name
      node_ip        = vm.ip
      cp_ip          = local.control_plane_ip
      token          = var.kubeadm_token
      ca_hash        = data.external.ca_hash.result.hash
      pod_cidr       = var.pod_network_cidr
      calico_version = var.calico_version
    })
  }
  # Render complete cloud-init YAML for every VM.
  user_data = {
    for name, vm in var.vms : name => templatefile("${path.module}/cloud-init/cloud-init.yml.tftpl", {#change file name
      role               = vm.role
      hostname           = name
      ssh_authorized_key = var.ssh_authorized_key
      ca_cert_pem        = tls_self_signed_cert.ca.cert_pem
      ca_key_pem         = tls_private_key.ca.private_key_pem
      bootstrap_script   = local.bootstrap_scripts[name]
    })
  }
}

# Cloud-Init Disks
# Creates one cloud-init ISO per VM.
# Cloud-init uses these ISO files to configure each VM during first boot.
resource "libvirt_cloudinit_disk" "ubuntu" {
  for_each = var.vms
  # Use a predictable ISO name based on the VM name.
  name      = "${each.key}-cloudinit.iso"
  user_data = local.user_data[each.key]
  meta_data = yamlencode({
    # Give cloud-init a stable identity for this VM.
    instance-id = each.key
    # Set the guest's local hostname to the Terraform map key.
    local-hostname = each.key
  })
}

# Kubernetes Virtual Machines
resource "libvirt_domain" "ubuntu" {
  for_each    = var.vms
  name        = each.key
  type        = "kvm"
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.vcpu
  cpu = {
    mode = "host-passthrough"
  }

  # Define the guest firmware, architecture, machine type, and boot order.
  os = {
    type = "hvm" #hardware-virtualized machine.
    # Create an x86-64 guest.
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  devices = {
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          file = {
            # Attach this VM's writable disk.
            file = libvirt_volume.ubuntu_disk[each.key].path
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        # Attach the cloud-init ISO as a CD-ROM device.
        device = "cdrom"
        source = {
          file = {
            # Attach the cloud-init ISO made for this VM.
            file = libvirt_cloudinit_disk.ubuntu[each.key].path
          }
        }
        target = {
          # Expose the ISO as the second disk on a SATA bus.
          dev = "sdb"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        mac = {
          address = each.value.mac
        }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.monitor_k8s.name
          }
        }

        wait_for_ip = {
          # Wait up to five minutes for libvirt to report a DHCP lease.
          timeout = 300
          # Obtain the address from the libvirt DHCP lease.
          source = "lease"
        }
      }
    ]
    serials = [
      {
        type = "pty"
      }
    ]

    consoles = [
      {
        type        = "pty"
        target_type = "serial"
        target_name = "serial0"
      }
    ]
  }
}

