variable "name" {
  description = "Name to give to the vm."
  type        = string
}

variable "vcpus" {
  description = "Number of vcpus to assign to the vm"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory in MiB"
  type        = number
  default     = 8192
}

variable "volume_id" {
  description = "Id of the disk volume to attach to the vm"
  type        = string
}

variable "libvirt_networks" {
  description = "Parameters of libvirt network connections if a libvirt networks are used."
  type = list(object({
    network_name = string
    network_id = string
    prefix_length = string
    ip = string
    mac = string
    gateway = string
    dns_servers = list(string)
  }))
  default = []
}

variable "macvtap_interfaces" {
  description = "List of macvtap interfaces."
  type        = list(object({
    interface     = string
    prefix_length = string
    ip            = string
    mac           = string
    gateway       = string
    dns_servers   = list(string)
  }))
  default = []
}

variable "cloud_init_volume_pool" {
  description = "Name of the volume pool that will contain the cloud init volume"
  type        = string
}

variable "cloud_init_volume_name" {
  description = "Name of the cloud init volume"
  type        = string
  default = ""
}

variable "ssh_admin_user" { 
  description = "Pre-existing ssh admin user of the image"
  type        = string
  default     = "ubuntu"
}

variable "admin_user_password" { 
  description = "Optional password for admin user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_admin_public_key" {
  description = "Public ssh part of the ssh key the admin will be able to login as"
  type        = string
}

variable "haproxy" {
  description = "Haproxy configuration parameters"
  sensitive   = true
  type        = object({
    postgres_nodes_max_count   = number
    postgres_nameserver_ips    = list(string)
    postgres_domain            = string
    patroni_client             = object({
      ca_key                           = string
      ca_certificate                   = string
      certificate_validity_period      = number
      certificate_early_renewal_period = number
    })
    timeouts                   = object({
      connect = string
      check   = string
      idle    = string
    })
  })
}

variable "fluentd" {
  description = "Fluentd configurations"
  sensitive   = true
  type = object({
    enabled = bool,
    load_balancer_tag = string,
    node_exporter_tag = string,
    forward = object({
      domain = string,
      port = number,
      hostname = string,
      shared_key = string,
      ca_cert = string,
    }),
    buffer = object({
      customized = bool,
      custom_value = string,
    })
  })
  default = {
    enabled = false
    load_balancer_tag = ""
    node_exporter_tag = ""
    forward = {
      domain = ""
      port = 0
      hostname = ""
      shared_key = ""
      ca_cert = ""
    }
    buffer = {
      customized = false
      custom_value = ""
    }
  }
}

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type        = object({
    enabled = bool,
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number,
      limit = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools = []
    makestep = {
      threshold = 0,
      limit = 0
    }
  }
}

variable "container_registry" {
  description = "Parameters for the container registry"
  sensitive   = true
  type        = object({
    url      = string,
    username = string,
    password = string
  })
  default = {
    url      = ""
    username = ""
    password = ""
  }
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type = bool
  default = true
}