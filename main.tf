locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_config = templatefile(
    "${path.module}/files/network_config.yaml.tpl", 
    {
      macvtap_interfaces = var.macvtap_interfaces
    }
  )
  network_interfaces = length(var.macvtap_interfaces) == 0 ? [{
    network_id = var.libvirt_network.network_id
    macvtap = null
    addresses = [var.libvirt_network.ip]
    mac = var.libvirt_network.mac != "" ? var.libvirt_network.mac : null
    hostname = var.name
  }] : [for macvtap_interface in var.macvtap_interfaces: {
    network_id = null
    macvtap = macvtap_interface.interface
    addresses = null
    mac = macvtap_interface.mac
    hostname = null
  }]
  fluentd_conf = templatefile(
    "${path.module}/files/fluentd.conf.tpl", 
    {
      fluentd = var.fluentd
      fluentd_buffer_conf = var.fluentd.buffer.customized ? var.fluentd.buffer.custom_value : file("${path.module}/files/fluentd_buffer.conf")
    }
  )
  container_params = {
    fluentd = var.fluentd.enabled ? "--log-driver=fluentd --log-opt fluentd-address=127.0.0.1:28080 --log-opt fluentd-retry-wait=1s --log-opt fluentd-max-retries=3600 --log-opt fluentd-sub-second-precision=true --log-opt tag=${var.fluentd.load_balancer_tag}" : ""
    config = var.container_registry.url != "" ? "--config /opt/docker" : ""
  }
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/user_data.yaml.tpl", 
      {
        node_name = var.name
        ssh_admin_public_key = var.ssh_admin_public_key
        ssh_admin_user = var.ssh_admin_user
        admin_user_password = var.admin_user_password
        chrony = var.chrony
        fluentd = var.fluentd
        fluentd_conf = local.fluentd_conf
        patroni_client_certificate = tls_locally_signed_cert.patroni_client_certificate.cert_pem
        patroni_client_key = tls_private_key.patroni_client_key.private_key_pem
        haproxy = var.haproxy
        haproxy_config = templatefile(
          "${path.module}/files/lb-haproxy.cfg",
          {
            haproxy = var.haproxy
          }
        )
        container_registry = var.container_registry
        container_params = local.container_params
      }
    )
  }
}

resource "libvirt_cloudinit_disk" "postgres_lb_node" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = length(var.macvtap_interfaces) > 0 ? local.network_config : null
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "postgres_lb_node" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  disk {
    volume_id = var.volume_id
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.postgres_lb_node.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}