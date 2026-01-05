# OCI Block Volume StorageClass for AutoMQ
# Use Ultra High Performance (20 VPUs/GB) to provide the highest IOPS performance
# Suitable for Kafka/AutoMQ's WAL and metadata storage needs
resource "kubernetes_storage_class_v1" "automq_oke_storage" {
  metadata {
    name = "automq-oke-storage"
    labels = {
      "app"         = "automq"
      "provisioner" = "oci-block-volume-csi"
      "managed-by"  = "terraform"
    }
  }

  # OCI Block Volume CSI Driver
  storage_provisioner = "blockvolume.csi.oraclecloud.com"

  # Reclaim Policy: Automatically delete the underlying Block Volume when deleting the PVC
  reclaim_policy = "Delete"

  # Volume Binding Mode: Wait for the Pod to be scheduled before creating the volume (ensures the volume and Pod are in the same availability domain)
  volume_binding_mode = "WaitForFirstConsumer"

  # Allow dynamic volume expansion
  allow_volume_expansion = true

  # Storage Parameters
  parameters = {
    # Attachment Type: Use paravirtualized for better performance
    attachment-type = "paravirtualized"

    # Performance Level: Ultra High Performance
    # VpusPerGB = 20 provides 120-225 IOPS/GB (depending on volume size)
    # Reference: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/blockvolumeperformance.htm
    vpusPerGB = "20"
  }

  # Depends on the completion of the OKE cluster creation
  depends_on = [module.oke]
}
