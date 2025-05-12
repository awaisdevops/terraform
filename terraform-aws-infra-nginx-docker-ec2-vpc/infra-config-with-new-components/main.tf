# Configure AWS provider
provider "aws" {                        # Start AWS provider block
  region = "eu-central-1"               # Set AWS region to Frankfurt (eu-central-1)
}

# Declare variables for flexible configuration
variable vpc_cidr_block {}              # Variable for VPC CIDR block
variable subnet_1_cidr_block {}         # Variable for subnet CIDR block
variable avail_zone {}                  # Variable for availability zone
variable env_prefix {}                  # Variable for environment prefix (used in tags)
variable instance_type {}               # Variable for EC2 instance type
variable ssh_key {}                    # Variable for path to SSH public key file
variable my_ip {}                      # Variable for user's IP address (for SSH access)

# Data source to fetch the latest Amazon Linux 2 AMI dynamically
data "aws_ami" "amazon-linux-image" {  # Define data source "amazon-linux-image"
  most_recent = true                   # Get the most recent AMI
  owners      = ["amazon"]             # Owned by Amazon

  filter {                            # Filter by AMI name pattern
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]  # Match Amazon Linux 2 AMI pattern
  }

  filter {                            # Filter by virtualization type
    name   = "virtualization-type"
    values = ["hvm"]                  # Hardware Virtual Machine
  }
}

# Output the AMI ID for reference
output "ami_id" {                     # Output block for AMI ID
  value = data.aws_ami.amazon-linux-image.id  # Value is the AMI ID from data source
}

# Create a VPC with specified CIDR block
resource "aws_vpc" "myapp-vpc" {     # Define VPC resource named "myapp-vpc"
  cidr_block = var.vpc_cidr_block    # Assign CIDR block from variable
  tags = {                          # Add tags to VPC
      Name = "${var.env_prefix}-vpc"  # Tag Name with env prefix and "vpc"
  }
}

# Create a subnet inside the VPC
resource "aws_subnet" "myapp-subnet-1" {  # Define subnet resource named "myapp-subnet-1"
  vpc_id = aws_vpc.myapp-vpc.id            # Attach subnet to the created VPC
  cidr_block = var.subnet_1_cidr_block     # Assign subnet CIDR block from variable
  availability_zone = var.avail_zone       # Specify availability zone from variable
  tags = {                                # Add tags to subnet
      Name = "${var.env_prefix}-subnet-1"  # Tag Name with env prefix and "subnet-1"
  }
}

# Create a security group with ingress and egress rules
resource "aws_security_group" "myapp-sg" {  # Define security group "myapp-sg"
  name   = "myapp-sg"                        # Security group name
  vpc_id = aws_vpc.myapp-vpc.id              # Associate with the VPC

  ingress {                                # Ingress rule for SSH access
    from_port   = 22                       # From port 22 (SSH)
    to_port     = 22                       # To port 22
    protocol    = "tcp"                    # TCP protocol
    cidr_blocks = [var.my_ip]              # Allow only from specified IP
  }

  ingress {                                # Ingress rule for app port 8080
    from_port   = 8080                     # From port 8080
    to_port     = 8080                     # To port 8080
    protocol    = "tcp"                    # TCP protocol
    cidr_blocks = ["0.0.0.0/0"]            # Allow from anywhere
  }

  egress {                                 # Egress rule for all outbound traffic
    from_port       = 0                    # From port 0 (all ports)
    to_port         = 0                    # To port 0
    protocol        = "-1"                 # All protocols
    cidr_blocks     = ["0.0.0.0/0"]        # Allow to anywhere
    prefix_list_ids = []                   # No prefix lists
  }

  tags = {                                # Tag security group
    Name = "${var.env_prefix}-sg"          # Tag Name with env prefix and "sg"
  }
}

# Create an Internet Gateway for VPC internet access
resource "aws_internet_gateway" "myapp-igw" {  # Define Internet Gateway "myapp-igw"
	vpc_id = aws_vpc.myapp-vpc.id                  # Attach IGW to the VPC
    
    tags = {                                    # Add tags to IGW
     Name = "${var.env_prefix}-internet-gateway"  # Tag Name with env prefix
   }
}

# Create a route table with default route to Internet Gateway
resource "aws_route_table" "myapp-route-table" {  # Define route table "myapp-route-table"
   vpc_id = aws_vpc.myapp-vpc.id                    # Associate with VPC

   route {                                         # Define a route
     cidr_block = "0.0.0.0/0"                      # Route all IPv4 traffic
     gateway_id = aws_internet_gateway.myapp-igw.id  # Route via Internet Gateway
   }

   # Note: Default local route is implicit and not specified here

   tags = {                                        # Tag route table
     Name = "${var.env_prefix}-route-table"        # Tag Name with env prefix
   }
 }

# Associate subnet with the route table
resource "aws_route_table_association" "a-rtb-subnet" {  # Associate route table with subnet
  subnet_id      = aws_subnet.myapp-subnet-1.id          # Subnet ID
  route_table_id = aws_route_table.myapp-route-table.id  # Route table ID
}

# Create an SSH key pair resource from a local public key file
resource "aws_key_pair" "ssh-key" {                # Define key pair resource "ssh-key"
  key_name   = "myapp-key"                          # Name of the key pair
  public_key = file(var.ssh_key)                    # Load public key from file path variable
}

# Output the public IP of the first EC2 instance
output "server-ip" {                                # Output block for EC2 public IP
    value = aws_instance.myapp-server.public_ip    # Value is the public IP of EC2 instance
}

# Provision the first EC2 instance with Docker and Nginx setup
resource "aws_instance" "myapp-server" {            # Define EC2 instance resource "myapp-server"
  ami                         = data.aws_ami.amazon-linux-image.id  # Use latest Amazon Linux 2 AMI
  instance_type               = var.instance_type          # Instance type from variable
  key_name                    = "myapp-key"                # Use created SSH key pair
  associate_public_ip_address = true                      # Assign public IP address
  subnet_id                   = aws_subnet.myapp-subnet-1.id  # Place instance in subnet
  vpc_security_group_ids      = [aws_security_group.myapp-sg.id]  # Attach security group
  availability_zone           = var.avail_zone             # Specify availability zone

  tags = {                                              # Tag the EC2 instance
    Name = "${var.env_prefix}-server"                   # Tag Name with env prefix and "server"
  }

  user_data = <<EOF                                     # User data script to run on instance launch
                 #!/bin/bash
                 apt-get update && apt-get install -y docker-ce  # Update and install Docker
                 systemctl start docker                              # Start Docker service
                 usermod -aG docker ec2-user                         # Add ec2-user to Docker group
                 docker run -p 8080:8080 nginx                        # Run Nginx container on port 8080
              EOF
}

# Provision the second EC2 instance with the same Docker and Nginx setup
resource "aws_instance" "myapp-server-two" {          # Define second EC2 instance "myapp-server-two"
  ami                         = data.aws_ami.amazon-linux-image.id  # Use latest Amazon Linux 2 AMI
  instance_type               = var.instance_type          # Instance type from variable
  key_name                    = "myapp-key"                # Use created SSH key pair
  associate_public_ip_address = true                      # Assign public IP address
  subnet_id                   = aws_subnet.myapp-subnet-1.id  # Place instance in subnet
  vpc_security_group_ids      = [aws_security_group.myapp-sg.id]  # Attach security group
  availability_zone           = var.avail_zone             # Specify availability zone

  tags = {                                              # Tag the EC2 instance
    Name = "${var.env_prefix}-server-two"                # Tag Name with env prefix and "server-two"
  }

  user_data = <<EOF                                     # User data script to run on instance launch
                 #!/bin/bash
                 apt-get update && apt-get install -y docker-ce  # Update and install Docker
                 systemctl start docker                              # Start Docker service
                 usermod -aG docker ec2-user                         # Add ec2-user to Docker group
                 docker run -p 8080:8080 nginx                        # Run Nginx container on port 8080
              EOF
}

