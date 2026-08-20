# A Lambda roda na VPC do cluster (subnets privadas) e acessa o RDS pelo SG do
# repo de banco. Pré-requisito: applies de tc-infra-kubernetes e tc-infra-database.
data "terraform_remote_state" "kubernetes" {
  backend = "s3"
  config = {
    bucket = "tc-fase3-tfstate-538880133939"
    key    = "infra-kubernetes/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "tc-fase3-tfstate-538880133939"
    key    = "infra-database/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  vpc_id                = data.terraform_remote_state.kubernetes.outputs.vpc_id
  private_subnets       = data.terraform_remote_state.kubernetes.outputs.private_subnets
  rds_security_group_id = data.terraform_remote_state.database.outputs.rds_security_group_id
  database_url_secret   = data.terraform_remote_state.database.outputs.database_url_secret_name
  jwt_secret_name       = data.terraform_remote_state.database.outputs.jwt_secret_name
}
