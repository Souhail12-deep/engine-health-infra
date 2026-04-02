terraform {
  backend "s3" {
    bucket         = "engine-health-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}
