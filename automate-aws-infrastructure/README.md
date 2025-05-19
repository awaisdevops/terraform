## Demo Project - Automate AWS Infrastructure

### Topics of the Demo Project
Automate AWS Infrastructure

### Technologies Used
- Terraform
- AWS
- Docker
- Linux
- Git

### Project Description
- Create a Terraform project to automate provisioning AWS infrastructure and its components, such as: VPC, Subnet, Route Table, Internet Gateway, EC2, Security Group
- Configure a Terraform script to automate deploying Docker container to EC2 instance

#### Steps to automate provisioning AWS infrastructure and its components

**Step 1:** Create a `terraform` folder
```sh
mkdir terraform
cd terraform
```

**Step 2:** Create a VPC and a Subnet\
Let's start with a `main.tf` file with the following content:

_terraform/main.tf_
```conf
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable env_prefix {}
variable avail_zone {}
variable vpc_cidr_block {}
variable subnet_cidr_block {}

resource "aws_vpc" "myapp-vpc" {
    cidr_block = var.vpc_cidr_block
    tags = {
        Name = "${var.env_prefix}-vpc"
    }
}

resource "aws_subnet" "myapp-subnet-1" {
    vpc_id = aws_vpc.myapp-vpc.id
    cidr_block = var.subnet_cidr_block
    availability_zone = var.avail_zone
    tags = {
        Name = "${var.env_prefix}-subnet-1"
    }
}
```

Create a `terraform.tfvars` file setting the four variables:

_terraform/terraform.tfvars_
```conf
env_prefix = "dev"
avail_zone = "eu-central-1a"
vpc_cidr_block = "10.0.0.0/16"
subnet_cidr_block = "10.0.10.0/24"
```

Apply the changes:
```sh
terraform apply --auto-approve
# ...
# aws_vpc.myapp-vpc: Creating...
# aws_vpc.myapp-vpc: Creation complete after 2s [id=vpc-09d8a5e6df029965c]
# aws_subnet.myapp-subnet-1: Creating...
# aws_subnet.myapp-subnet-1: Creation complete after 0s [id=subnet-049b7bc24b07a9ca7]
# 
# Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

**Step 3:** Create a Route Table & Internet Gateway\
Add the following resources to the `main.tf` file:

_terraform/main.tf_
```conf
resource "aws_internet_gateway" "myapp-igw" {
    vpc_id = aws_vpc.myapp-vpc.id
    tags = {
        Name = "${var.env_prefix}-igw"
    }
}

resource "aws_default_route_table" "main-rtb" {
    default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
        Name = "${var.env_prefix}-main-rtb"
    }
}
```

Apply the changes:
```sh
terraform apply --auto-approve
# aws_internet_gateway.myapp-igw: Creating...
# aws_internet_gateway.myapp-igw: Creation complete after 0s [id=igw-0376d90b54fcef3ad]
# aws_default_route_table.main-rtb: Creating...
# aws_default_route_table.main-rtb: Creation complete after 1s [id=rtb-0ee7bd1fb740d6ba3]
# 
# Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

**Step 4:** Create a Security Group\
To configure firewall rules for the EC2 instance we want to create (open port 22 for ssh and port 8080 to access the nginx server), we need to create a security group.

- Add `variable my_ip {}` to the variable definitions in the `main.tf` file.
- Add `my_ip = "31.10.152.229/32"` (or whatever your current IP address is) to the `terraform.tfvars` file.
- Add the following resource to the `main.tf` file:\
  _terraform/main.tf_
  ```conf
  resource "aws_default_security_group" "default-sg" {
      vpc_id = aws_vpc.myapp-vpc.id
  
      ingress {
          from_port = 22
          to_port = 22
          protocol = "tcp"
          cidr_blocks = [var.my_ip]
      }
  
      ingress {
          from_port = 8080
          to_port = 8080
          protocol = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
      }
  
      egress {
          from_port = 0
          to_port = 0
          protocol = "-1"
          cidr_blocks = ["0.0.0.0/0"]
          prefix_list_ids = []
      }
  
      tags = {
          Name = "${var.env_prefix}-default-sg"
      }
  }
  ```

Apply the changes:
```sh
terraform apply --auto-approve
```

**Step 5:** Select the Amazon Machine Image (AMI) for EC2\
We need the id of the Amazon Machine Image (AMI) which will be used as a template for the EC2 virtual machine. Instead of hardcoding it into the configuration file, we define a `data` querying the latest version of the image we want to use (the AMI name can be found in the AWS Management Console under EC2 > AMI Catalog > Community AMIs):

_terraform/main.tf_
```conf
data "aws_ami" "latest-amazon-linux-image" {
    most_recent = true
    owners = ["amazon"]
    filter {
        name = "name"
        values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
    }
    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}
```

To test whether the `data` queries the expected AMI add the following `output` to the configuration:

_terraform/main.tf_
```conf
output "aws_ami_id" {
    value = data.aws_ami.latest-amazon-linux-image.id
}
```

**Step 6:** Create an EC2 instance\
We can reference the `data` in the resource definition for the EC2 instance:

_terraform/main.tf_
```conf
resource "aws_instance" "myapp-server" {
    ami = data.aws_ami.latest-amazon-linux-image.id
}
```

The second required attribute is the `instance_type`. We set it to `t2.micro` but don't write it hardcoded into the configuration file, but rather define a variable and add the value to the `terraform.tfvars` file:

_terraform/main.tf_
```conf
variable instance_type {}
...
resource "aws_instance" "myapp-server" {
    ami = data.aws_ami.latest-amazon-linux-image.id
    instance_type = var.instance_type
}
```

_terraform/terraform.tfvars_
```conf
...
instance_type = "t2.micro"
```

All the other attributes are optional but we set some of them because we want the EC2 to be running in our VPC and use our security group and so on. The final resource definition will look like this:

_terraform/main.tf_
```conf
resource "aws_instance" "myapp-server" {
    ami = data.aws_ami.latest-amazon-linux-image.id
    instance_type = var.instance_type

    subnet_id = aws_subnet.myapp-subnet-1.id
    vpc_security_group_ids = [aws_default_security_group.default-sg.id]
    availability_zone = var.avail_zone

    associate_public_ip_address = true
    key_name = aws_key_pair.ssh-key.key_name

    tags = {
        Name = "${var.env_prefix}-server"
    }
}
```

To get the public IP address when applying the configuration file, we can add the following `output` configuration:

_terraform/main.tf_
```conf
output "ec2_public_ip" {
    value = aws_instance.myapp-server.public_ip
}
```

For being able to ssh into the EC2 instance we have to create a key pair. The name of the key pair is then set as the value of the attribute `key_name`.

If you haven't created a private/public key-pair yet, execute `ssh-keygen -t ed25519` to do so.

To store the public key on the EC2 instance add the following content to the configuration file:

_terraform/main.tf_
```conf
variable public_key_location {}
...
resource "aws_key_pair" "ssh-key" {
    key_name = "server-key"
    public_key = file(var.public_key_location)
}
```

Set the `public_key_location` variable in the 'terraform.tfvars' file:

_terraform/terraform.tfvars_
```conf
public_key_location = "/Users/fsiegrist/.ssh/id_ed25519.pub"
```

Apply the changes:
```sh
terraform apply --auto-approve
# ...
# aws_instance.myapp-server: Creating...
# aws_instance.myapp-server: Still creating... [10s elapsed]
# aws_instance.myapp-server: Still creating... [20s elapsed]
# aws_instance.myapp-server: Creation complete after 22s [id=i-0b063121922c765b6]
# ...
# Outputs:
# 
# aws_ami_id = "ami-08e415170f52d1657"
# ec2_public_ip = "3.72.36.170"
```

**Step 7:** SSH into the created EC2 instance (optional)\
As soon as the EC2 instance state in the AWS Management Console is 'Running' we can ssh into the instance. Execute the following command in your local machine's terminal:
```sh
ssh ec2-user@3.72.36.170
```

#### Steps to configure a Terraform script to automate deploying Docker container to EC2 instance

**Step 1:** Create a shell script for installing Docker and running an nginx container\
Create a file called `entry-script.sh` with the following content:

_terraform/entry-script.sh_
```sh
#!/bin/bash

# install and start docker
sudo yum update -y && sudo yum install -y docker
sudo systemctl start docker

# add ec2-user to docker group to allow it to call docker commands
sudo usermod -aG docker ec2-user

# start a docker container running nginx
docker run -p 8080:80 nginx
```

**Step 2:** Make the script be executed when the EC2 instance is initialized\
To execute this script on the EC2 instance when it is initialized add the following `user_data` block just before the `tags` attribute inside the `aws_instance` resource:

_terraform/main.tf_
```conf
user_data = file("entry-script.sh")
```

Apply the changes:
```sh
terraform apply --auto-approve
# ...
# Outputs:
# 
# aws_ami_id = "ami-08e415170f52d1657"
# ec2_public_ip = "3.67.138.246"
```

Open the browser and navigate to `http://3.67.138.246:8080`. You should see the nginx welcome page.

You can also ssh into the EC2 instance and execute `docker ps` to see the nginx container:
```sh
ssh ec2-user@3.67.138.246
docker ps
# CONTAINER ID   IMAGE     COMMAND                  CREATED         STATUS         PORTS                                   NAMES
# 30eafbc1406c   nginx     "/docker-entrypoint.…"   4 seconds ago   Up 3 seconds   0.0.0.0:8080->80/tcp, :::8080->80/tcp   laughing_spence
```
