terraform {
  backend "s3" {
    bucket         = "engine-health-terraform-state-123456"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}
