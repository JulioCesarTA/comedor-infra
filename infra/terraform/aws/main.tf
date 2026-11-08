terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

provider "aws" { region = var.region }

variable "region"       { default = "us-east-1" }
variable "project"      { default = "comedor-uagrm" }
variable "cluster_name" { default = "eks-comedor" }

# ---------- EKS ----------
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  eks_managed_node_groups = {
    default = { desired_size = 3, min_size = 2, max_size = 6, instance_types = ["t3.large"] }
  }
}

module "vpc" {
  source          = "terraform-aws-modules/vpc/aws"
  version         = "~> 5.13"
  name            = "${var.project}-vpc"
  cidr            = "10.10.0.0/16"
  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
  enable_nat_gateway = true
}

# ---------- DynamoDB (SPEC §1 — transversal) ----------
resource "aws_dynamodb_table" "idempotency" {
  name         = "idempotency_keys"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idempotencyKey"
  attribute { name = "idempotencyKey", type = "S" }
}

resource "aws_dynamodb_table" "sagas" {
  name         = "sagas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sagaId"
  attribute { name = "sagaId", type = "S" }
}

# ---------- SNS topics ----------
resource "aws_sns_topic" "dominio_menu"     { name = "dominio-menu" }
resource "aws_sns_topic" "dominio_reservas" { name = "dominio-reservas" }
resource "aws_sns_topic" "dominio_pagos"    { name = "dominio-pagos" }

# ---------- SQS cola CQRS projector ----------
resource "aws_sqs_queue" "cqrs_projector_dlq" { name = "cqrs-projector-dlq" }
resource "aws_sqs_queue" "cqrs_projector" {
  name = "cqrs-projector"
  redrive_policy = jsonencode({ deadLetterTargetArn = aws_sqs_queue.cqrs_projector_dlq.arn, maxReceiveCount = 5 })
}

# ---------- S3 bucket para fotos de bandejas ----------
resource "aws_s3_bucket" "bandejas" { bucket = "${var.project}-bandejas-fotos" }

# ---------- ECR registries ----------
resource "aws_ecr_repository" "menu_inventario" { name = "menu-inventario-service" }
resource "aws_ecr_repository" "ia_ml"           { name = "ia-ml-service" }
resource "aws_ecr_repository" "api_gateway"     { name = "api-gateway" }

output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "ecr_registry"     { value = split("/", aws_ecr_repository.menu_inventario.repository_url)[0] }
