provider "tencentcloud" {
  # Authentication is handled via environment variables:
  #   export TENCENTCLOUD_SECRET_ID="your-secret-id"
  #   export TENCENTCLOUD_SECRET_KEY="your-secret-key"
  region = var.region
}
