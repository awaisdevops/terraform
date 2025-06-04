variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

# RE-INTRODUCED: Variables for existing key pair
variable "key_pair_name" {
  description = "The name of your existing EC2 Key Pair in AWS."
  type        = string
}

variable "private_key_path" {
  description = "The local path to your EC2 private key (.pem file) for SSH access."
  type        = string
}

variable "ec2_user" {
  description = "The username for SSH access to the EC2 instance (e.g., ec2-user for Amazon Linux)."
  type        = string
  default     = "ec2-user"
}

variable "s3_bucket_name" {
  description = "The base name for the S3 bucket. A random suffix will be added."
  type        = string
  default     = "my-app-data"
}
