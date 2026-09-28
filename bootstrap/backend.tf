terraform {
  backend "s3" {
    bucket       = "url-shortener-tfstate-sss3333"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}