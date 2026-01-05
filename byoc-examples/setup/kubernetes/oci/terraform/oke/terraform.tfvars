# Basic Configuration
tenancy_ocid     = "ocid1.tenancy.oc1..xxxx"
compartment_id   = "ocid1.compartment.oc1..xxxx"
region           = "us-ashburn-1"
oke_cluster_name = "automq-dev-oke"
oci_profile      = "DEFAULT"

vcn_id                  = "ocid1.vcn.oc1.iad.xxxx"
worker_subnet_id        = "ocid1.subnet.oc1.iad.xxxx"
pod_subnet_id           = "ocid1.subnet.oc1.iad.xxxx"
control_plane_subnet_id = "ocid1.subnet.oc1.iad.xxxx"
lb_subnet_id            = "ocid1.subnet.oc1.iad.xxxx"

control_plane_is_public = true
# Node Configuration
node_config = {
  node_type        = "VM.Standard.E5.Flex"
  ocpus            = 2
  size             = 3
  memory           = 16
  boot_volume_size = 50
}

