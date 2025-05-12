# Configure AWS provider
provider "aws" {                      # Start AWS provider block
    region = "eu-west-3"              # Set AWS region to Paris (eu-west-3)
}

# Declare variables for flexible configuration
variable vpc_cidr_block {}            # Variable for VPC CIDR block
variable subnet_cidr_block {}         # Variable for subnet CIDR block
variable avail_zone {}                # Variable for availability zone
variable env_prefix {}                # Variable for environment prefix (used in tags)
variable my_ip {}                    # Variable for user's IP address (for SSH access)
variable instance_type {}             # Variable for EC2 instance type
variable public_key_location {}      # Variable for path to public SSH key file

# Create a VPC with specified CIDR block
resource "aws_vpc" "myapp-vpc" {     # Define VPC resource named "myapp-vpc"
    cidr_block = var.vpc_cidr_block  # Assign CIDR block from variable
    tags = {                         # Add tags to VPC
        Name = "${var.env_prefix}-vpc"  # Tag Name with env prefix and "vpc"
    }
}

# Create a subnet inside the VPC
resource "aws_subnet" "myapp-subnet-1" {  # Define subnet resource named "myapp-subnet-1"
    vpc_id = aws_vpc.myapp-vpc.id          # Attach subnet to the created VPC
    cidr_block = var.subnet_cidr_block     # Assign subnet CIDR block from variable
    availability_zone = var.avail_zone     # Specify availability zone from variable
    tags = {                              # Add tags to subnet
        Name = "${var.env_prefix}-subnet-1"  # Tag Name with env prefix and "subnet-1"
    }
}

# Create an Internet Gateway for VPC internet access
resource "aws_internet_gateway" "myapp-igw" {  # Define Internet Gateway resource "myapp-igw"
    vpc_id = aws_vpc.myapp-vpc.id                 # Attach IGW to the VPC
    tags = {                                    # Add tags to IGW
        Name = "${var.env_prefix}-igw"          # Tag Name with env prefix and "igw"
    }
}

# Configure default route table to route outbound traffic through IGW
resource "aws_default_route_table" "main-rtb" {  # Define default route table resource "main-rtb"
    default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id  # Use VPC's default route table

    route {                                      # Define a route
        cidr_block = "0.0.0.0/0"                 # Route all IPv4 traffic
        gateway_id = aws_internet_gateway.myapp-igw.id  # Route via Internet Gateway
    }
    tags = {                                    # Add tags to route table
        Name = "${var.env_prefix}-main-rtb"     # Tag Name with env prefix and "main-rtb"
    }
}

# Define default security group for VPC with ingress and egress rules
resource "aws_default_security_group" "default-sg" {  # Define default security group "default-sg"
    vpc_id = aws_vpc.myapp-vpc.id                        # Associate with the VPC

    ingress {                                            # Ingress rule for SSH access
        from_port = 22                                   # From port 22 (SSH)
        to_port = 22                                     # To port 22
        protocol = "tcp"                                 # TCP protocol
        cidr_blocks = [var.my_ip]                        # Allow only from specified IP
    }

    ingress {                                            # Ingress rule for app port 8080
        from_port = 8080                                 # From port 8080
        to_port = 8080                                   # To port 8080
        protocol = "tcp"                                 # TCP protocol
        cidr_blocks = ["0.0.0.0/0"]                      # Allow from anywhere
    }

    egress {                                             # Egress rule for all outbound traffic
        from_port = 0                                    # From port 0 (all ports)
        to_port = 0                                      # To port 0
        protocol = "-1"                                  # All protocols
        cidr_blocks = ["0.0.0.0/0"]                      # Allow to anywhere
        prefix_list_ids = []                             # No prefix lists
    }

    tags = {                                            # Tag security group
        Name = "${var.env_prefix}-default-sg"           # Tag Name with env prefix and "default-sg"
    }
}

# Commented out alternative security group rules (not active)
# /*
# resource "aws_security_group_rule" "web-http" {        # Define ingress rule for HTTP port 8080
#   security_group_id = aws_vpc.myapp-vpc.default_security_group_id  # Attach to default SG
#   type              = "ingress"                        # Ingress rule
#   from_port         = 8080                             # From port 8080
#   to_port           = 8080                             # To port 8080
#   protocol          = "tcp"                            # TCP protocol
#   cidr_blocks       = ["0.0.0.0/0"]                    # Allow from anywhere
# }
#
# resource "aws_security_group_rule" "server-ssh" {      # Define ingress rule for SSH port 22
#   security_group_id = aws_vpc.myapp-vpc.default_security_group_id  # Attach to default SG
#   type              = "ingress"                        # Ingress rule
#   from_port         = 22                               # From port 22
#   to_port           = 22                               # To port 22
#   protocol          = "tcp"                            # TCP protocol
#   cidr_blocks       = [var.my_ip]                      # Allow from specified IP
# }
# */

# Data source to fetch the latest Amazon Linux 2 AMI dynamically
data "aws_ami" "latest-amazon-linux-image" {    # Define data source "latest-amazon-linux-image"
    most_recent = true                          # Get the most recent AMI
    owners = ["amazon"]                         # Owned by Amazon

    filter {                                   # Filter by AMI name pattern
        name = "name"                          
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]  # Match Amazon Linux 2 AMI pattern
    }
    filter {                                   # Filter by virtualization type
        name = "virtualization-type"
        values = ["hvm"]                       # Hardware Virtual Machine
    }
}

# Output the AMI ID for reference
output "aws_ami_id" {                          # Output block for AMI ID
    value = data.aws_ami.latest-amazon-linux-image.id  # Value is the AMI ID from data source
}

# Output the public IP of the EC2 instance
output "ec2_public_ip" {                        # Output block for EC2 public IP
    value = aws_instance.myapp-server.public_ip  # Value is the public IP of EC2 instance
}

# Create an AWS key pair resource from a local public key file
resource "aws_key_pair" "ssh-key" {             # Define key pair resource "ssh-key"
    key_name = "server-key"                      # Name of the key pair
    public_key = file(var.public_key_location)  # Load public key from file path variable
}

# Provision an EC2 instance with specified AMI and configuration
resource "aws_instance" "myapp-server" {        # Define EC2 instance resource "myapp-server"
    ami = data.aws_ami.latest-amazon-linux-image.id  # Use latest Amazon Linux 2 AMI
    instance_type = var.instance_type            # Instance type from variable

    subnet_id = aws_subnet.myapp-subnet-1.id    # Place instance in created subnet
    vpc_security_group_ids = [aws_default_security_group.default-sg.id]  # Attach security group
    availability_zone = var.avail_zone           # Specify availability zone

    associate_public_ip_address = true           # Assign public IP address
    key_name = aws_key_pair.ssh-key.key_name    # Use created SSH key pair

    user_data = file("entry-script.sh")          # Run user data script on instance launch

    tags = {                                    # Tag the EC2 instance
        Name = "${var.env_prefix}-server"       # Tag Name with env prefix and "server"
    }
}

