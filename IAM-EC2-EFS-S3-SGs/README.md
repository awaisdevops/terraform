# Automated AWS Infrastructure Deployment with Terraform (EC2, VPC, IAM, EFS, S3)

This Terraform project automates the deployment of an AWS EC2 instance within a dedicated VPC. It sets up an IAM role for the instance, enabling it to interact with S3 and EFS. The project also creates and attaches both EFS (Elastic File System) and S3 (Simple Storage Service) storage to the EC2 instance, with appropriate security group configurations.

---

## Project Overview

The core purpose of this setup is to provide an EC2 instance with its own isolated network, granular access permissions via IAM, and two types of persistent storage solutions:

* **Dedicated VPC:** Ensures your EC2 instance runs on single-tenant hardware, providing isolation.
* **IAM Role & Instance Profile:** Grants the EC2 instance specific permissions to interact with other AWS services (S3 and EFS) without storing credentials directly on the instance.
* **EC2 Instance:** The compute resource where your applications can run.
* **Security Groups:** Controls network traffic to and from the EC2 instance and EFS, enforcing security rules.
* **EFS (Elastic File System):** A scalable, elastic, cloud-native NFS file system for shared data access.
* **S3 (Simple Storage Service) Bucket:** Object storage for various data types, mounted on the EC2 instance for easy access.

---

## Prerequisites

Before deploying this infrastructure, ensure you have the following:

1.  **AWS Account:** An active AWS account.
2.  **AWS CLI Configured:** The AWS Command Line Interface (CLI) installed and configured with appropriate credentials (e.g., using `aws configure`).
3.  **Terraform Installed:** Terraform (v1.0+) installed on your local machine.
4.  **Existing SSH Key Pair:** An SSH Key Pair already created in your AWS EC2 service in the target region. You will need both its name (in AWS) and the local path to its private key file (`.pem`).
    * **Security Note:** Keep your private key file (`.pem`) secure and never commit it to version control. Set strict file permissions (e.g., `chmod 400 /path/to/your/key.pem`).

---

## Project Structure

The project consists of three main Terraform files:

* `main.tf`: Defines the AWS resources to be created (VPC, EC2, IAM, EFS, S3, Security Groups).
* `variables.tf`: Declares input variables for customizable settings.
* `outputs.tf`: Defines output values that will be displayed after Terraform applies the configuration.

---

## Terraform Configuration (`main.tf`)

```terraform
# main.tf

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
  key_name      = var.key_pair_name # Reference the name of your existing EC2 Key Pair
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
```

---

## Variables (`variables.tf`)

Customize your deployment by setting values for these variables.

```terraform
# variables.tf
variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

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
```

---

## Outputs (`outputs.tf`)

These outputs provide useful information about the deployed resources after `terraform apply`.

```terraform
# outputs.tf
output "vpc_id" {
  description = "The ID of the dedicated VPC."
  value       = aws_vpc.dedicated_vpc.id
}

output "ec2_instance_public_ip" {
  description = "The public IP address of the EC2 instance."
  value       = aws_instance.my_ec2_instance.public_ip
}

output "ec2_instance_private_ip" {
  description = "The private IP address of the EC2 instance."
  value       = aws_instance.my_ec2_instance.private_ip
}

output "efs_file_system_id" {
  description = "The ID of the EFS file system."
  value       = aws_efs_file_system.my_efs.id
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket created."
  value       = aws_s3_bucket.my_s3_bucket.id
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance."
  value       = "ssh -i ${var.private_key_path} ${var.ec2_user}@${aws_instance.my_ec2_instance.public_ip}"
}
```

---

## Explanation of Resources

### 1. Dedicated VPC & Networking

* **`aws_vpc.dedicated_vpc`**: Creates a new Virtual Private Cloud with a `/16` CIDR block. `instance_tenancy = "dedicated"` isolates your instances on single-tenant hardware.
* **`aws_subnet.public_subnet`**: A public subnet within the VPC where the EC2 instance will reside. `map_public_ip_on_launch = true` ensures the instance gets a public IP.
* **`aws_internet_gateway.igw`**: Enables communication between your VPC and the internet.
* **`aws_route_table.public_route_table`**: Defines a route that sends all internet-bound traffic (`0.0.0.0/0`) through the Internet Gateway.
* **`aws_route_table_association.public_subnet_association`**: Links the route table to the public subnet.

### 2. Security Groups

* **`aws_security_group.ec2_instance_sg`**: This security group is attached to the EC2 instance.
    * **Inbound Rules:** Allows SSH (port 22), HTTP (port 80), HTTPS (port 443), and custom application ports (8080, 8796) from anywhere (`0.0.0.0/0`). **For production, restrict `cidr_blocks` to known IP ranges.**
    * **Outbound Rule:** Allows all outbound traffic (`-1`).
* **`aws_security_group.efs_security_group`**: This security group is attached to the EFS mount target.
    * **Inbound Rule:** Allows NFS (port 2049) traffic **only from the `ec2_instance_sg`**. This ensures only your EC2 instance (or other instances in that security group) can mount the EFS.

### 3. IAM Role for EC2 Instance

* **`aws_iam_role.ec2_s3_efs_role`**: Creates an IAM role that EC2 instances can assume. The `assume_role_policy` explicitly grants this permission.
* **`aws_iam_role_policy_attachment`**: Attaches two AWS managed policies to the role:
    * `AmazonS3FullAccess`: Grants full access to S3. **For production, replace with a custom policy granting only necessary S3 permissions (least privilege).**
    * `AmazonElasticFileSystemClientFullAccess`: Grants full client access to EFS. **Similarly, restrict this in production.**
* **`aws_iam_instance_profile.ec2_s3_efs_profile`**: A container for the IAM role that can be assigned to an EC2 instance. This is how the EC2 instance gets its permissions.

### 4. EC2 Instance

* **`aws_instance.my_ec2_instance`**: Defines the EC2 instance.
    * `ami`: Uses a `data` source to fetch the latest Amazon Linux 2 AMI dynamically.
    * `instance_type`: Set to `t2.micro` (free-tier eligible).
    * `subnet_id`: Places the instance in the public subnet.
    * `vpc_security_group_ids`: Attaches the `ec2_instance_sg` to the instance.
    * **`key_name = var.key_pair_name`**: This crucial line assigns your **existing** SSH key pair to the instance.
    * **`iam_instance_profile = aws_iam_instance_profile.ec2_s3_efs_profile.name`**: Assigns the IAM role, granting S3 and EFS access permissions.
    * `user_data`: A shell script that runs on first boot to install `amazon-efs-utils` and `s3fs-fuse`, and creates mount points.

### 5. EFS Storage

* **`aws_efs_file_system.my_efs`**: Creates the EFS file system. `encrypted = true` is highly recommended.
* **`aws_efs_mount_target.my_efs_mount_target`**: Creates a network interface in the specified subnet that EC2 instances can use to mount the EFS. It's associated with `efs_security_group`.
* **`aws_efs_access_point.my_efs_access_point`**: (Optional but good practice) Provides an application-specific entry point into the EFS, simplifying path management and enforcing user/group IDs.
* **`local-exec` Provisioner (for EFS mount):** This provisioner runs `ssh` commands from your local machine to the EC2 instance *after* it's created. It installs `amazon-efs-utils`, mounts the EFS, and adds an entry to `/etc/fstab` for automatic remounting on reboot. It uses your provided `private_key_path` for SSH authentication.

### 6. S3 Storage

* **`aws_s3_bucket.my_s3_bucket`**: Creates a new S3 bucket with a unique name (using `random_string`).
* **`aws_s3_bucket_versioning`**: Enables versioning on the S3 bucket for data protection.
* **`aws_s3_bucket_public_access_block`**: **Highly recommended for security.** This resource ensures the S3 bucket is not publicly accessible.
* **`local-exec` Provisioner (for S3 mount):** Similar to EFS, this provisioner uses `ssh` to connect to the EC2 instance, install `s3fs-fuse`, and mount the S3 bucket. It leverages the EC2 instance's IAM role (`iam_role=auto`) for secure authentication with S3, avoiding direct credential storage on the instance.

---

## How to Deploy

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/awaisdevops/terraform.git
    cd IAM-EC2-EFS-S3-SGs
    ```

2.  **Configure Variables:**
    Create a `terraform.tfvars` file in the same directory as your `main.tf`.
    **Important:** Add `terraform.tfvars` to your `.gitignore` file to prevent sensitive information from being committed to version control.

    ```hcl
    # terraform.tfvars
    aws_region       = "us-east-1" # Your desired AWS region
    key_pair_name    = "your-existing-ec2-key-name" # e.g., "my-ssh-key"
    private_key_path = "/path/to/your/secure/my-ssh-key.pem" # e.g., "~/.ssh/my-ssh-key.pem"
    ec2_user         = "ec2-user" # Default for Amazon Linux AMIs
    s3_bucket_name   = "my-unique-app-data-bucket" # Must be globally unique
    ```
    Alternatively, you can export these as environment variables (`export TF_VAR_key_pair_name=...`) or pass them directly on the command line (`terraform apply -var="key_pair_name=..."`).

3.  **Initialize Terraform:**
    Navigate to the project root directory in your terminal and run:
    ```bash
    terraform init
    ```
    This command initializes the working directory, downloads necessary providers (AWS, random), and sets up the backend.

4.  **Review the Plan:**
    To see what Terraform will create, modify, or destroy, run:
    ```bash
    terraform plan
    ```
    Carefully review the proposed changes to ensure they match your expectations.

5.  **Apply the Configuration:**
    If the plan looks correct, apply the changes:
    ```bash
    terraform apply
    ```
    Terraform will prompt you to confirm by typing `yes`.

---

## Verification

After `terraform apply` completes successfully, check the `outputs.tf` section for important details.

1.  **Connect to EC2 Instance:**
    Use the `ssh_command` output to connect to your instance:
    ```bash
    ssh -i /path/to/your/secure/my-ssh-key.pem ec2-user@<EC2_PUBLIC_IP>
    ```
    Replace `<EC2_PUBLIC_IP>` with the value from the `ec2_instance_public_ip` output.

2.  **Verify Mounted Storage:**
    Once connected to the EC2 instance, run the following commands to check if EFS and S3 are mounted:
    ```bash
    df -h
    ```
    You should see entries for `/mnt/efs` (EFS) and `/mnt/s3bucket` (S3) with their respective sizes.

    You can test writing data:
    ```bash
    sudo touch /mnt/efs/test_efs_file.txt
    sudo touch /mnt/s3bucket/test_s3_file.txt
    ls /mnt/efs/
    ls /mnt/s3bucket/
    ```
    You can also verify the S3 object in the AWS S3 console.

---

## Cleanup

To destroy all the AWS resources created by this Terraform configuration, run:

```bash
terraform destroy
```
Terraform will show you the resources it plans to destroy and prompt you to confirm by typing `yes`.

---

## Important Security Notes

* **SSH Private Key:** Your local private key file is paramount for SSH access. **Never share it, and never commit it to version control.**
* **IAM Policies:** The `AmazonS3FullAccess` and `AmazonElasticFileSystemClientFullAccess` policies are broad. In a production environment, you should create **custom IAM policies** that grant only the minimum necessary permissions to your EC2 instance role (principle of least privilege).
* **Security Groups:** The security groups in this example allow SSH, HTTP, HTTPS, and custom ports from `0.0.0.0/0` (anywhere). For production, **restrict inbound traffic** to specific IP ranges or other security groups.
* **Session Manager:** For enhanced security and keyless access to EC2 instances, consider integrating AWS Systems Manager Session Manager into your workflow. This eliminates the need to open port 22 or manage SSH keys on the instance.
