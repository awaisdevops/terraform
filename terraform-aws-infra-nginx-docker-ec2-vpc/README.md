# Terraform AWS EC2 Deployment

This project demonstrates a practical use case of deploying infrastructure on AWS using Terraform. The goal is to provision a virtual server (EC2 instance) running an NGINX Docker container, entirely within a custom network environment.

![Image](infra-config-with-new-components/project1.png)

## Key Components:

- **Create Custom VPC** – Define a virtual private network to isolate AWS resources.
- **Create Custom Subnet** – Allocate a specific IP range within the VPC in one availability zone.
- **Create Route Table and Internet Gateway** – Enable internet connectivity for resources in the subnet.
- **Provision an EC2 Instance** – Launch a virtual server to host applications or services.
- **Deploy Nginx Docker Container** – Run a lightweight web server inside the EC2 using Docker.
- **Create Security Group (Firewall)** – Configure access rules to allow HTTP and SSH traffic.

This setup follows best practices by provisioning all infrastructure components from scratch, avoiding AWS default resources, and allowing for clean teardown when no longer needed.

---

## Creating VPC and Subnet:

A custom VPC and subnet are provisioned in a chosen availability zone with internet access via an Internet Gateway. Terraform variables are used to parameterize CIDR blocks, availability zone, and environment-based naming, clearly separated from default AWS components.

---

## Route Table and Internet Gateway:

Upon creating a custom VPC, AWS automatically generates a default route table and network ACL for internal traffic and subnet-level firewall rules. To enable internet connectivity, a new Internet Gateway and custom route table are provisioned using Terraform. This route table explicitly routes all outbound traffic (0.0.0.0/0) through the Internet Gateway. Tags and environment-based prefixes are applied consistently, and Terraform handles resource dependencies automatically during provisioning.

---

## Subnet Association with Route Table:

To route internet-bound traffic from our subnet, we must explicitly associate it with the custom route table that includes the Internet Gateway route. By default, subnets are associated with the main route table of the VPC, which may lack internet connectivity. Using Terraform’s `aws_route_table_association` resource, we bind the custom subnet to the correct route table, ensuring that all outbound traffic (e.g., SSH or web access) from resources like EC2 instances is properly routed via the Internet Gateway.

---

## Use Main/Default Route Table:

Instead of creating a custom route table, you can configure the default route table provided by AWS for your VPC using the `aws_default_route_table` resource. By referencing the default route table ID (available via the VPC resource), you can add a route to the Internet Gateway, enabling outbound traffic. Since subnets not explicitly associated with any route table are automatically linked to the main one, this approach simplifies configuration by eliminating the need for separate route table creation and subnet association.

---

## Security Group:

To allow SSH access (port 22) and web access to the NGINX container (port 8080) on the EC2 instance, a custom security group is created using the `aws_security_group` resource. It includes two ingress rules: one restricted to your local IP for SSH, and another open to the world for HTTP access. The egress rule allows all outbound traffic to enable package installations and Docker image pulls. To keep IP-specific variables (like your local IP) secure and configurable, these are stored in a local `terraform.tfvars` file excluded from version control. Terraform also supports using the default security group instead of creating a new one, if preferred.

---

## Amazon Machine Image (AMI) for EC2:

Now we'll configure an AWS EC2 instance using Terraform, started from setting up a VPC, subnet, Internet Gateway, and security group with open ports 22 and 80. We'll dynamically select the latest Amazon Linux AMI (Amazon Machine Image) using data sources and filters, rather than hardcoding the AMI ID, ensuring the configuration remains up-to-date across regions and image updates. We also use filters for attributes like image name and virtualization type, and how to validate the selected AMI with Terraform outputs before deploying the instance.

---

## Create EC2 Instance:

We configure an AWS EC2 instance using Terraform, focusing on best practices such as parameterizing the instance type and availability zone, explicitly assigning the instance to a custom VPC, subnet, and security group, and securely managing SSH key pairs for access. It covers associating a public IP for connectivity, handling key permissions for secure SSH access, and demonstrates the full workflow from configuration to instance creation, verification, and secure login, ensuring a reproducible and secure infrastructure setup.

---

## Automate SSH Key Pair:

We also automate the creation and management of SSH key pairs for AWS EC2 instances, eliminating manual steps such as generating keys, copying files, and configuring permissions. By defining the key pair as a Terraform resource and allowing users to specify their public key or its file path as a variable, the setup becomes reusable and adaptable for different team members. This approach ensures infrastructure is fully codified, simplifies environment replication, and reduces the risk of manual errors or forgotten resources during cleanup, aligning with best practices for infrastructure as code.

---

## Run Entrypoint Script to Start Docker Container:

We automate AWS EC2 instance provisioning with user data scripts that install Docker, start the service, add the default user to the Docker group, and launch an Nginx container on port 80. This fully automates server setup and container deployment, ensuring a ready-to-use environment immediately after instance creation.

---

## Extract to Shell Script:

Instead of running entrypoint script, we'll configure Terraform to run the external shell scripts in Terraform’s user data for cleaner infrastructure provisioning. While Terraform automates instance creation and initial setup, it’s limited in managing ongoing server configuration and application deployment. For those tasks, complementary tools like Ansible or Puppet are recommended to handle application-level automation beyond Terraform’s scope.

---

## Example Configuration:

### `terraform.tfvars`

```hcl
vpc_cidr_block = "10.0.0.0/16"           # CIDR block for the VPC, defines the IP address range for the network
subnet_cidr_block = "10.0.10.0/24"       # CIDR block for the subnet within the VPC
avail_zone = "ap-northeast-2c"            # Availability zone where resources will be deployed (Seoul region)
env_prefix = "dev"                        # Environment prefix used for naming/tagging resources (e.g., dev, prod)
my_ip = "110.93.205.18/32"                # Your public IP address with mask, used for restricting SSH access
instance_type = "t2.micro"                 # EC2 instance type specifying hardware configuration
public_key_location = "/home/machine/.ssh/id_rsa.pub"  # File path to your public SSH key for EC2 access
````

### `main.tf`

```hcl
provider "aws" {
  region = "eu-central-1"
}

variable vpc_cidr_block {}
variable subnet_1_cidr_block {}
variable avail_zone {}
variable env_prefix {}
variable instance_type {}
variable ssh_key {}
variable my_ip {}

data "aws_ami" "amazon-linux-image" {
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

output "ami_id" {
  value = data.aws_ami.amazon-linux-image.id
}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
      Name = "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet-1" {
  vpc_id = aws_vpc.myapp-vpc.id
  cidr_block = var.subnet_1_cidr_block
  availability_zone = var.avail_zone
  tags = {
      Name = "${var.env_prefix}-subnet-1"
  }
}

resource "aws_security_group" "myapp-sg" {
  name   = "myapp-sg"
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.env_prefix}-sg"
  }
}

resource "aws_internet_gateway" "myapp-igw" {
	vpc_id = aws_vpc.myapp-vpc.id
    
    tags = {
     Name = "${var.env_prefix}-internet-gateway"
   }
}

resource "aws_route_table" "myapp-route-table" {
   vpc_id = aws_vpc.myapp-vpc.id

   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.myapp-igw.id
   }

   # default route, mapping VPC CIDR block to "local", created implicitly and cannot be specified.

   tags = {
     Name = "${var.env_prefix}-route-table"
   }
 }

# Associate subnet with Route Table
resource "aws_route_table_association" "a-rtb-subnet" {
  subnet_id      = aws_subnet.myapp-subnet-1.id
  route_table_id = aws_route_table.myapp-route-table.id
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "myapp-key"
  public_key = file(var.ssh_key)
}

output "server-ip" {
    value = aws_instance.myapp-server.public_ip
}

resource "aws_instance" "myapp-server" {
  ami                         = data.aws_ami.amazon-linux-image.id
  instance_type               = var.instance_type
  key_name                    = "myapp-key"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids      = [aws_security_group.myapp-sg.id]
  availability_zone			      = var.avail_zone

  tags = {
    Name = "${var.env_prefix}-server"
  }

  user_data = <<EOF
                 #!/bin/bash
                 apt-get update && apt-get install -y docker-ce
                 systemctl start docker
                 user
```

### initialize

    terraform init

### preview terraform actions

    terraform plan

### apply configuration with variables

    terraform apply -var-file terraform-dev.tfvars

### destroy a single resource

    terraform destroy -target aws_vpc.myapp-vpc

### destroy everything fromtf files

    terraform destroy

### show resources and components from current state

    terraform state list

### show current state of a specific resource/data

    terraform state show aws_vpc.myapp-vpc    

### set avail_zone as custom tf environment variable - before apply

    export TF_VAR_avail_zone="eu-west-3a"
