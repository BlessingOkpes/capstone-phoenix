#!/bin/bash
# Run this ONCE, before `terraform init`, from your control EC2 instance.
# Creates the S3 bucket + DynamoDB lock table that hold Terraform's remote state.
set -e

REGION="us-east-1"
BUCKET_NAME="capstone-phoenix-tfstate-$(whoami)-$RANDOM"   # must be globally unique
TABLE_NAME="capstone-phoenix-tf-lock"

echo "Creating S3 bucket: $BUCKET_NAME"
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"

aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Creating DynamoDB lock table: $TABLE_NAME"
aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo ""
echo "=========================================="
echo "Bucket:  $BUCKET_NAME"
echo "Table:   $TABLE_NAME"
echo "Region:  $REGION"
echo "=========================================="
echo "Now edit backend.tf and put these exact values in, then run: terraform init"
