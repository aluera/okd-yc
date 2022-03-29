provider "yandex" {
    token     = ""
    cloud_id  = ""
    folder_id = ""
}

### Datasource
data "yandex_client_config" "client" {}


### Networking
locals {
  folder_id = data.yandex_client_config.client.folder_id
}
resource "yandex_vpc_network" "this" {
  description = var.network_description
  name        = var.network_name
  labels      = var.labels
  folder_id   = local.folder_id
}

resource "yandex_vpc_subnet" "this" {
  for_each       = { for v in var.subnets : v.v4_cidr_blocks => v }
  name           = each.value.zone
  description    = "${var.network_name} subnet for zone ${each.value.zone}"
  v4_cidr_blocks = [each.value.v4_cidr_blocks]
  zone           = each.value.zone
  network_id     = yandex_vpc_network.this.id
  folder_id      = local.folder_id
  dhcp_options {
    domain_name = var.dns_zone_name
  }

  labels = var.labels
}

# Allowed port
resource "yandex_vpc_security_group" "all_to_all" {
  name        = "all-to-all"
  description = "Internally, the following ports need to be reachable from all machines to all machines of okd"
  network_id  = yandex_vpc_network.this.id
  folder_id   = local.folder_id

  labels = var.labels

  ingress {
    protocol       = "TCP"
    description    = "Yandex.Cloud specific. allows health_checks from load-balancer health check address range, needed for HA cluster to work as well as for load balancer services to work"
    v4_cidr_blocks = ["198.18.235.0/24", "198.18.248.0/24"]
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "TCP"
    description    = "allows ssh to nodes from private addresses"
    v4_cidr_blocks = flatten([for v in yandex_vpc_subnet.this : v.v4_cidr_blocks])
    port           = 22
  }
  ingress {
    protocol       = "ICMP"
    description    = "allows icmp from private subnets for troubleshooting"
    v4_cidr_blocks = flatten([for v in yandex_vpc_subnet.this : v.v4_cidr_blocks])
  }

  ingress {
    protocol          = "TCP"
    description       = "rule for api"
    predefined_target = "self_security_group"
    port              = 6443
  }
  ingress {
    protocol          = "TCP"
    description       = "rule for machine config through internal NLB"
    predefined_target = "self_security_group"
    port              = 22623
  }
  ingress {
    protocol          = "TCP"
    description       = "rule for etcd"
    predefined_target = "self_security_group"
    from_port         = 2379
    to_port           = 2380
  }
  ingress {
    protocol          = "TCP"
    description       = "rule for host services"
    predefined_target = "self_security_group"
    from_port         = 9000
    to_port           = 9999
  }
  ingress {
    protocol          = "TCP"
    description       = "rule for kubernetes"
    predefined_target = "self_security_group"
    from_port         = 10249
    to_port           = 10259
  }
  ingress {
    protocol          = "UDP"
    description       = "rule for vxlan/geneve"
    predefined_target = "self_security_group"
    port              = 4789
  }
  ingress {
    protocol          = "UDP"
    description       = "rule for vxlan/geneve"
    predefined_target = "self_security_group"
    port              = 6081
  }
  ingress {
    protocol          = "UDP"
    description       = "rule for host services"
    predefined_target = "self_security_group"
    from_port         = 9000
    to_port           = 9999
  }
  ingress {
    protocol          = "UDP"
    description       = "rule for node port"
    predefined_target = "self_security_group"
    from_port         = 30000
    to_port           = 32767
  }

  egress {
    protocol       = "ANY"
    description    = "rule for internet access"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "ssh_in" {
  name        = "pub-all-ssh"
  description = "Allow external ssh"
  network_id  = yandex_vpc_network.this.id
  folder_id   = local.folder_id

  labels = var.labels

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
}

resource "yandex_vpc_security_group" "local-allow-all" {
  name        = "local-allow-all"
  description = "Allow internal traffic"
  network_id  = yandex_vpc_network.this.id
  folder_id   = local.folder_id

  labels = var.labels

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["10.88.0.0/16"]
  }
}

resource "yandex_vpc_security_group" "nlb_master" {
  name        = "pub-nlb--okd"
  description = "Public Load Balancer <--> master for access"
  network_id  = yandex_vpc_network.this.id
  folder_id   = local.folder_id

  labels = var.labels

  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }
  ingress {
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22623
  }
}
resource "yandex_vpc_security_group" "nlb_worker" {
  name        = "pub-nlb--workers"
  description = "Public Load Balancer <--> worker for ingress"
  network_id  = yandex_vpc_network.this.id
  folder_id   = local.folder_id

  labels = var.labels

  dynamic "ingress" {
    for_each = ["443", "80"]
    content {
      protocol       = "TCP"
      v4_cidr_blocks = ["0.0.0.0/0"]
      port           = ingress.value
    }
  }
}
## LB Target groups
resource "yandex_lb_target_group" "master" {
  name      = "okd-master"
  folder_id = local.folder_id

  dynamic "target" {
    for_each = flatten([for v in yandex_compute_instance.master : {
      subnet_id = v.network_interface.0.subnet_id,
      address   = v.network_interface.0.ip_address
    }])
    content {
      subnet_id = target.value.subnet_id
      address   = target.value.address
    }
  }
}
resource "yandex_lb_target_group" "worker" {
  name      = "okd-worker"
  folder_id = local.folder_id

  dynamic "target" {
    for_each = flatten([for v in yandex_compute_instance.worker : {
      subnet_id = v.network_interface.0.subnet_id,
      address   = v.network_interface.0.ip_address
    }])
    content {
      subnet_id = target.value.subnet_id
      address   = target.value.address
    }
  }
}

resource "yandex_lb_target_group" "bootstrap" {
  name      = "okd-bootstrap"
  folder_id = local.folder_id

  dynamic "target" {
    for_each = flatten([for v in yandex_compute_instance.bootstrap : {
      subnet_id = v.network_interface.0.subnet_id,
      address   = v.network_interface.0.ip_address
    }])
    content {
      subnet_id = target.value.subnet_id
      address   = target.value.address
    }
  }
}


## LB targeted to masters and bootstrap for mgmt and API connection
resource "yandex_vpc_address" "addr_api" {
  name      = "okd-ip-api"
  labels    = var.labels
  folder_id = local.folder_id
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}


resource "yandex_lb_network_load_balancer" "public_api" {
  name        = "okd-external-api"
  labels      = var.labels
  folder_id   = local.folder_id
  description = "NLB for public access to cluster API. "
  type        = "external"

  listener {
    name = "api-listener"
    port = 6443
    external_address_spec {
      address = yandex_vpc_address.addr_api.external_ipv4_address[0].address
    }
  }
  listener {
    name = "machine-config-listener"
    port = 22623
    external_address_spec {
      address = yandex_vpc_address.addr_api.external_ipv4_address[0].address
    }
  }
  attached_target_group {
    target_group_id = yandex_lb_target_group.master.id
    healthcheck {
      name                = "tcp"
      interval            = 10
      unhealthy_threshold = 3
      healthy_threshold   = 2
      timeout             = 5

      tcp_options {
        port = 6443
        #path = "/readyz"
      }
    }
  }

  dynamic "attached_target_group" {
    for_each = yandex_compute_instance.bootstrap
    content {
      target_group_id = yandex_lb_target_group.bootstrap.id
      healthcheck {
        name                = "tcp"
        interval            = 10
        unhealthy_threshold = 3
        healthy_threshold   = 2
        timeout             = 5

        tcp_options {
          port = 6443
        }
      }
    }
  }
}
##LB targeted to workers. For access to apps 
resource "yandex_vpc_address" "addr_apps" {
  name      = "okd-ip-apps"
  labels    = var.labels
  folder_id = local.folder_id
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}
resource "yandex_lb_network_load_balancer" "public_apps" {
  name        = "okd-external-apps"
  labels      = var.labels
  folder_id   = local.folder_id
  description = "NLB for public access okd based apps. "
  type        = "external"

  listener {
    name = "https-listener"
    port = 443
    external_address_spec {
      address = yandex_vpc_address.addr_apps.external_ipv4_address[0].address
    }
  }
  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      address = yandex_vpc_address.addr_apps.external_ipv4_address[0].address
    }
  }
  attached_target_group {
    target_group_id = yandex_lb_target_group.worker.id
    healthcheck {
      name = "tcp"
      tcp_options {
        port = 443
        #path = "/healthz"
      }
    }
  }
}



resource "yandex_dns_zone" "private_zone" {
  name             = "okd-zone-private"
  description      = "zone for service discovery for okd"
  folder_id        = local.folder_id
  labels           = var.labels
  zone             = var.dns_zone_name
  public           = false
  private_networks = [yandex_vpc_network.this.id]
}

resource "yandex_dns_recordset" "api_int" {
  zone_id = yandex_dns_zone.private_zone.id
  name    = "api-int.${var.cluster_name}"
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr_api.external_ipv4_address[0].address]
}
resource "yandex_dns_recordset" "api" {
  zone_id = yandex_dns_zone.private_zone.id
  name    = "api.${var.cluster_name}"
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr_api.external_ipv4_address[0].address]
}
resource "yandex_dns_recordset" "bastion" {
  zone_id = yandex_dns_zone.private_zone.id
  name    = "bastion-internet.${var.cluster_name}"
  type    = "A"
  ttl     = 200
  data    = [yandex_compute_instance.bastion.network_interface[0].nat_ip_address]
}

### Wildcard entry
resource "yandex_dns_recordset" "apps_int" {
  zone_id = yandex_dns_zone.private_zone.id
  name    = "*.apps.${var.cluster_name}"
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr_apps.external_ipv4_address[0].address]
}

### Bastion Host
resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  platform_id = "standard-v3"
  folder_id   = local.folder_id
  hostname    = "bastion"
  zone        = element(flatten([for v in yandex_vpc_subnet.this : v.zone]), 0)

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      type     = var.type_disk
      size     = "16"
    }
  }

  network_interface {
    nat                = true
    subnet_id          = element(flatten([for v in yandex_vpc_subnet.this : v.id]), 0)
    security_group_ids = [yandex_vpc_security_group.all_to_all.id, yandex_vpc_security_group.nlb_master.id, yandex_vpc_security_group.ssh_in.id]
    dns_record {
      fqdn = "bastion.${var.cluster_name}.${var.dns_zone_name}"
      ttl  = 600
      ptr  = true
    }
  }

  scheduling_policy {
    preemptible = true
  }
  metadata = {
    serial-port-enable = 1
    user-data          = "${file("../custom-ignition/bastion.ign")}"
  }


}


### S3 Object Storage for Ignition files
resource "yandex_iam_service_account" "sa_storage" {
  name        = "sa-storage-nnorienne"
  description = "service account to access s3"
}

resource "yandex_resourcemanager_folder_iam_member" "service_account" {
  folder_id = data.yandex_client_config.client.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa_storage.id}"
  role      = "storage.admin"
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa_storage.id
  description        = "static access key for object storage"
}


resource "yandex_storage_bucket" "okd_ignition_nnorienn" {
  bucket        = "okd-ignition-nnorienn"
  force_destroy = "true"
  grant {
    type        = "Group"
    permissions = ["READ", ]
    uri         = "http://acs.amazonaws.com/groups/global/AllUsers"
  }
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  depends_on = [
    yandex_resourcemanager_folder_iam_member.service_account,
  ]
}



resource "yandex_storage_object" "okd-okd_ignition_nnorienn" {
  bucket     = yandex_storage_bucket.okd_ignition_nnorienn.id
  acl        = "private"
  key        = "bootstrap.ign"
  source     = "../okd-ignition/bootstrap.ign"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}



## Bootstrap Host
resource "yandex_compute_instance" "bootstrap" {
  count       = var.bootstrap_count
  name        = "bootstrap"
  platform_id = "standard-v3"
  folder_id   = local.folder_id
  hostname    = "bootstrap"
  zone        = element(flatten([for v in yandex_vpc_subnet.this : v.zone]), 0)

  resources {
    cores  = 4
    memory = 16
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      type     = "network-ssd"
      size     = "100"
    }
  }

  network_interface {
    nat                = false
    subnet_id          = element(flatten([for v in yandex_vpc_subnet.this : v.id]), 0)
    security_group_ids = [yandex_vpc_security_group.all_to_all.id, yandex_vpc_security_group.nlb_master.id, yandex_vpc_security_group.ssh_in.id]
    dns_record {
      fqdn = "bootstrap.${var.cluster_name}.${var.dns_zone_name}"
      ttl  = 600
      ptr  = true
    }
  }

  scheduling_policy {
    preemptible = true
  }
  metadata = {
    serial-port-enable = 1
    user-data          = jsonencode({ "ignition" : { "config" : { "replace" : { "source" : "https://${yandex_storage_bucket.okd_ignition_nnorienn.bucket_domain_name}/bootstrap.ign" } }, "version" : "3.1.0" } })
  }


}

# Master Node[s]

resource "yandex_compute_instance" "master" {
  count                     = var.master_count
  name                      = "master${count.index}"
  platform_id               = "standard-v3"
  folder_id                 = local.folder_id
  hostname                  = "master${count.index}"
  zone                      = element(flatten([for v in yandex_vpc_subnet.this : v.zone]), count.index)
  allow_stopping_for_update = true

  resources {
    cores  = var.master_cpu
    memory = var.master_ram
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      type     = var.type_disk
      size     = "96"
    }
  }

  network_interface {
    nat                = false
    subnet_id          = element(flatten([for v in yandex_vpc_subnet.this : v.id]), count.index)
    security_group_ids = [yandex_vpc_security_group.all_to_all.id, yandex_vpc_security_group.nlb_master.id, yandex_vpc_security_group.local-allow-all.id]
    dns_record {
      fqdn = "master${count.index}.${var.cluster_name}.${var.dns_zone_name}"
      ttl  = 600
      ptr  = true
    }
  }

  scheduling_policy {
    preemptible = true
  }
  metadata = {
    serial-port-enable = 1
    user-data          = "${file("../okd-ignition/master.ign")}"
  }
  lifecycle {
    ignore_changes = [secondary_disk, labels["yandex.cloud/public-csi"]]
  }


}
### # Worker Node[s]
resource "yandex_compute_instance" "worker" {
  count                     = var.worker_count
  name                      = "worker${count.index}"
  platform_id               = "standard-v3"
  folder_id                 = local.folder_id
  hostname                  = "worker${count.index}"
  zone                      = element(flatten([for v in yandex_vpc_subnet.this : v.zone]), count.index)
  allow_stopping_for_update = true

  resources {
    cores  = var.worker_cpu
    memory = var.worker_ram
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      type     = var.type_disk
      size     = "96"
    }
  }

  network_interface {
    nat                = false
    subnet_id          = element(flatten([for v in yandex_vpc_subnet.this : v.id]), count.index)
    security_group_ids = [yandex_vpc_security_group.all_to_all.id, yandex_vpc_security_group.nlb_worker.id, yandex_vpc_security_group.local-allow-all.id]
    dns_record {
      fqdn = "worker${count.index}.${var.cluster_name}.${var.dns_zone_name}"
      ttl  = 600
      ptr  = true
    }
  }

  scheduling_policy {
    preemptible = true
  }
  metadata = {
    serial-port-enable = 1
    user-data          = "${file("../okd-ignition/worker.ign")}"
  }
  lifecycle {
    ignore_changes = [secondary_disk, labels["yandex.cloud/public-csi"]]
  }
}