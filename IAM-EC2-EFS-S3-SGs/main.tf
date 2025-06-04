# Configure the AWS provider
provider "aws" {
  region = "us-east-1" # Change to your desired AWS region
}

# 1. Create a dedicated VPC
resource "aws_vpc" "dedicated_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "dedicated" # Ensures EC2 instances run on dedicated tenancy
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "DedicatedVPC"
  }
}

# Create a subnet within the dedicated VPC
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.dedicated_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a" # Change to your desired AZ
  map_public_ip_on_launch = true # Allows EC2 instances to get a public IP

  tags = {
    Name = "PublicSubnet"
  }
}

# Create an Internet Gateway for the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dedicated_vpc.id

  tags = {
    Name = "DedicatedVPC_IGW"
  }
}

# Create a route table and associate it with the public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.dedicated_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Group for the EC2 instance with specified ports
resource "aws_security_group" "ec2_instance_sg" {
  name        = "ec2_instance_security_group"
  description = "Security group for EC2 instance with application ports"
  vpc_id      = aws_vpc.dedicated_vpc.id

  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow port 8080 from anywhere"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow port 8796 from anywhere"
    from_port   = 8796
    to_port     = 8796
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EC2InstanceSG"
  }
}

# Security Group for EFS storage
resource "aws_security_group" "efs_security_group" {
  name        = "efs_security_group"
  description = "Security group for EFS allowing NFS access from EC2 instances"
  vpc_id      = aws_vpc.dedicated_vpc.id

  # Allow inbound NFS traffic (port 2049) only from the EC2 instance's security group
  ingress {
    description     = "Allow NFS from EC2 Instance SG"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_instance_sg.id] # Reference the EC2 SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EFSSecurityGroup"
  }
}

# 2. Create an IAM Role for the EC2 instance
resource "aws_iam_role" "ec2_s3_efs_role" {
  name = "ec2_s3_efs_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "EC2S3EFSRole"
  }
}

# Attach policies to the IAM role (e.g., S3 read/write, EFS access)
resource "aws_iam_role_policy_attachment" "s3_access_policy_attachment" {
  role       = aws_iam_role.ec2_s3_efs_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" # Broad access for demo, restrict in production
}

resource "aws_iam_role_policy_attachment" "efs_access_policy_attachment" {
  role       = aws_iam_role.ec2_s3_efs_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess" # Broad access, restrict in production
}

# Create an IAM Instance Profile (container for the IAM role)
resource "aws_iam_instance_profile" "ec2_s3_efs_profile" {
  name = "ec2_s3_efs_profile"
  role = aws_iam_role.ec2_s3_efs_role.name
}

# 3. Create the EC2 instance
resource "aws_instance" "my_ec2_instance" {
  ami           = data.aws_ami.amazon_linux.id # Dynamically get the latest Amazon Linux 2 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_instance_sg.id]
  # REVERTED: Referencing an existing key pair by name
  key_name      = var.key_pair_name
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_efs_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y amazon-efs-utils
              sudo yum install -y s3fs-fuse

              # Create mount points
              sudo mkdir -p /mnt/efs
              sudo mkdir -p /mnt/s3bucket

              echo "EC2 setup complete!"
              EOF

  tags = {
    Name = "MyTerraformEC2Instance"
  }
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 4. Create EFS storage
resource "aws_efs_file_system" "my_efs" {
  creation_token = "my-efs-file-system"
  encrypted      = true # Recommended for data at rest encryption

  tags = {
    Name = "MyTerraformEFS"
  }
}

# Create EFS mount target in the same subnet as the EC2 instance
resource "aws_efs_mount_target" "my_efs_mount_target" {
  file_system_id = aws_efs_file_system.my_efs.id
  subnet_id      = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.efs_security_group.id]

  # Add a provisioner to mount EFS after the instance is running
  provisioner "local-exec" {
    command = <<-EOT
              echo "Waiting for EC2 instance to be ready..."
              sleep 60

              echo "Mounting EFS on EC2 instance..."
              # REVERTED: Use the user-provided private key path
              ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ${var.ec2_user}@${aws_instance.my_ec2_instance.public_ip} "sudo mount -t efs -o tls,accesspoint-id=${aws_efs_access_point.my_efs_access_point.id} ${aws_efs_file_system.my_efs.id}:/ /mnt/efs"
              ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ${var.ec2_user}@${aws_instance.my_ec2_instance.public_ip} "echo '${aws_efs_file_system.my_efs.id}:/ /mnt/efs efs _netdev,tls 0 0' | sudo tee -a /etc/fstab"
              EOT
    when = create
    depends_on = [aws_instance.my_ec2_instance, aws_efs_mount_target.my_efs_mount_target]
  }
}

# Create an EFS Access Point (optional but good for specific application access)
resource "aws_efs_access_point" "my_efs_access_point" {
  file_system_id = aws_efs_file_system.my_efs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/app_data" # Create a specific directory for the application
  }

  tags = {
    Name = "MyTerraformEFSAccessPoint"
  }
}


# 5. Create S3 storage (bucket)
resource "aws_s3_bucket" "my_s3_bucket" {
  bucket = "${var.s3_bucket_name}-${random_string.bucket_suffix.id}" # Unique bucket name

  tags = {
    Name = "MyTerraformS3Bucket"
  }
}

# Recommended: Enable versioning for S3 bucket
resource "aws_s3_bucket_versioning" "my_s3_bucket_versioning" {
  bucket = aws_s3_bucket.my_s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Recommended: Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "my_s3_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.my_s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Add a provisioner to mount S3 on the EC2 instance using s3fs
provisioner "local-exec" {
  command = <<-EOT
            echo "Waiting for EC2 instance to be ready for S3 mount..."
            sleep 90

            echo "Mounting S3 bucket on EC2 instance..."
            # REVERTED: Use the user-provided private key path
            ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ${var.ec2_user}@${aws_instance.my_ec2_instance.public_ip} "echo '${aws_s3_bucket.my_s3_bucket.id} /mnt/s3bucket fuse.s3fs _netdev,allow_other,iam_role=auto 0 0' | sudo tee -a /etc/fstab"
            ssh -o StrictHostKeyChecking=no -i ${var.private_key_path} ${var.ec2_user}@${aws_instance.my_ec2_instance.public_ip} "sudo mount /mnt/s3bucket"
            EOT
  when = create
  depends_on = [aws_instance.my_ec2_instance, aws_s3_bucket.my_s3_bucket]
}

# Generate a random string for unique S3 bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}
