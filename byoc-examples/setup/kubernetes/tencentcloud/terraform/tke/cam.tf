# CAM Role for AutoMQ node pool (CVM type)
resource "tencentcloud_cam_role" "automq_node_role" {
  name = local.cam_role_name
  document = jsonencode({
    version = "2.0"
    statement = [
      {
        effect = "allow"
        principal = {
          service = ["cvm.qcloud.com"]
        }
        action = "name/sts:AssumeRole"
      }
    ]
  })
  description = "CAM role for AutoMQ TKE node pool"
}

# CAM Policy from external JSON file
resource "tencentcloud_cam_policy" "automq_node_policy" {
  name        = "automq-node-policy-${local.suffix}"
  document    = file(var.cam_policy_file)
  description = "CAM policy for AutoMQ TKE node pool"
}

# Attach policy to role
resource "tencentcloud_cam_role_policy_attachment" "automq_node_role_policy" {
  role_id   = tencentcloud_cam_role.automq_node_role.id
  policy_id = tencentcloud_cam_policy.automq_node_policy.id
}
