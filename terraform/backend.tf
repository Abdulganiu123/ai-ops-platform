terraform {
  backend "s3" {
    bucket       = "bucket-for-devgen-terraform-state"
    key          = "devgen/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true


  }
}