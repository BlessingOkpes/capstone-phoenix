terraform {
  backend "s3" {
    # Fill these in with the values printed by bootstrap-backend.sh
    bucket         = "capstone-phoenix-tfstate-ubuntu-15371"
    key            = "capstone-phoenix/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "capstone-phoenix-tf-lock"
    encrypt        = true
  }
}
