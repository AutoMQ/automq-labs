terraform {
  required_version = ">= 1.9.0"
  required_providers { automq = { source = "automq/automq", version = "= 0.4.8" } }
}
provider "automq" {}
variable "instance_state_path" {
  type    = string
  default = "../instance/terraform.tfstate"
}
variable "kafka_password" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.kafka_password) >= 16 && !can(regex("[\\n\\r]", var.kafka_password))
    error_message = "Use a Kafka password with at least 16 characters and no line breaks."
  }
}
data "terraform_remote_state" "instance" {
  backend = "local"
  config  = { path = var.instance_state_path }
}
locals { instance = data.terraform_remote_state.instance.outputs }
resource "automq_kafka_topic" "smoke" {
  environment_id    = local.instance.environment_id
  kafka_instance_id = local.instance.instance_id
  name              = "eks-smoke"
  partition         = 1
}
resource "automq_kafka_user" "smoke" {
  environment_id    = local.instance.environment_id
  kafka_instance_id = local.instance.instance_id
  username          = "eks-smoke"
  password          = var.kafka_password
}
resource "automq_kafka_acl" "topic" {
  environment_id    = local.instance.environment_id
  kafka_instance_id = local.instance.instance_id
  resource_type     = "TOPIC"
  resource_name     = automq_kafka_topic.smoke.name
  pattern_type      = "LITERAL"
  principal         = "User:${automq_kafka_user.smoke.username}"
  operation_group   = "ALL"
  permission        = "ALLOW"
}
resource "automq_kafka_acl" "group" {
  environment_id    = local.instance.environment_id
  kafka_instance_id = local.instance.instance_id
  resource_type     = "GROUP"
  resource_name     = "eks-smoke-"
  pattern_type      = "PREFIXED"
  principal         = "User:${automq_kafka_user.smoke.username}"
  operation_group   = "ALL"
  permission        = "ALLOW"
}
output "topic" { value = automq_kafka_topic.smoke.name }
output "username" { value = automq_kafka_user.smoke.username }
