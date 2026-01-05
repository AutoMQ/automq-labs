data "oci_containerengine_clusters" "cluster" {
  compartment_id = var.compartment_id
  name           = local.cluster_name
  state          = ["ACTIVE"]

  depends_on = [null_resource.wait_for_cluster]
}

# OKE Module
module "oke" {
  source = "oracle-terraform-modules/oke/oci"

  providers = {
    oci.home = oci
  }

  compartment_id     = var.compartment_id
  cluster_name       = local.cluster_name
  kubernetes_version = "v1.33.1"

  create_vcn   = false
  vcn_id       = var.vcn_id
  region       = var.region
  cluster_type = "enhanced"
  cni_type     = "npn"

  create_bastion                    = false
  create_operator                   = false # Disable operator creation
  assign_public_ip_to_control_plane = var.control_plane_is_public
  control_plane_is_public           = var.control_plane_is_public
  control_plane_allowed_cidrs       = ["0.0.0.0/0"]
  output_detail                     = true

  worker_compartment_id = var.compartment_id
  worker_pool_mode      = "node-pool"
  worker_image_type     = "oke"

  subnets = {
    cp      = { create = "never", id = var.control_plane_subnet_id }
    workers = { create = "never", id = var.worker_subnet_id }
    pods    = { create = "never", id = var.pod_subnet_id }
    pub_lb  = { create = "never", id = var.lb_subnet_id }
  }

  worker_pools = {
    automq = {
      shape            = var.node_config.node_type
      ocpus            = var.node_config.ocpus
      memory           = var.node_config.memory
      size             = var.node_config.size
      boot_volume_size = var.node_config.boot_volume_size
      # Pod networking configuration for VCN Native
      max_pods_per_node = 31
      pod_subnet_id     = var.pod_subnet_id
    }
  }
}

resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command = "sleep 20"
  }
  depends_on = [module.oke]
}
