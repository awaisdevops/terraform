## Demo Project - Modularize Project

### Topics of the Demo Project
Modularize Project

### Technologies Used
- Terraform
- AWS
- Docker
- Linux
- Git

### Project Description
- Divide Terraform resources into reusable modules

#### Steps to divide Terraform resources into reusable modules

**Step 1:** Extract providers, variables and outputs to their own files\
It's a good practice to move the providers into a _providers.tf_ file, the variable definitions into their own _variables.tf_ file and the outputs into an _outputs.tf_ file. In the _main.tf_ file you will keep only the resources and data definitions.

So we end up with three new files:

_terraform/providers.tf_
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
```

_terraform/variables.tf_
```conf
variable env_prefix {}
variable avail_zone {}
variable vpc_cidr_block {}
variable subnet_cidr_block {}
variable my_ip {}
variable instance_type {}
variable public_key_location {}
```

_/terraform/outputs.tf_
```conf
output "aws_ami_id" {
    value = data.aws_ami.latest-amazon-linux-image.id
}

output "ec2_public_ip" {
    value = aws_instance.myapp-server.public_ip
}
```

The file _terraform/main.tf_ just contains the remaining resources and data definitions.

**Step 2:** Create empty folder and file structure for the modules\
We want to create two modules:
- a `subnet` module creating all the subnet related resources
- a `webserver` module creating all the EC2 instance related resources

Let's first create an empty folder and file structure:

```sh
mkdir modules

mkdir modules/subnet
touch modules/subnet/main.tf
touch modules/subnet/variables.tf
touch modules/subnet/outputs.tf

mkdir modules/webserver
touch modules/webserver/main.tf
touch modules/webserver/variables.tf
touch modules/webserver/outputs.tf
```

**Step 3:** Extract subnet related resources\
First let's extract the subnet related resources from the _terraform/main.tf_ file into the _terraform/modules/subnet/main.tf_ file. All the references to resources in the parent module have to be replaced by references to variables. And these variables have to be declared in the child module's _variables.tf_ file together with all the other variables referenced by the child module:

_terraform/modules/subnet/main.tf_
```conf
resource "aws_subnet" "myapp-subnet-1" {
    vpc_id = var.vpc_id                   # was aws_vpc.myapp-vpc.id
    cidr_block = var.subnet_cidr_block
    availability_zone = var.avail_zone
    tags = {
        Name = "${var.env_prefix}-subnet-1"
    }
}

resource "aws_internet_gateway" "myapp-igw" {
    vpc_id = var.vpc_id                   # was aws_vpc.myapp-vpc.id
    tags = {
        Name = "${var.env_prefix}-igw"
    }
}

resource "aws_default_route_table" "main-rtb" {
    default_route_table_id = var.default_route_table_id  # was aws_vpc.myapp-vpc.default_route_table_id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
        Name = "${var.env_prefix}-main-rtb"
    }
}
```

_terraform/modules/subnet/variables.tf_
```conf
variable env_prefix {}
variable avail_zone {}
variable subnet_cidr_block {}
variable vpc_id {}                  # new variable defined here
variable default_route_table_id {}  # new variable defined here
```

**Step 4:** Use the new subnet module
To reference the new child module from the root module, add the following `module` block to the root module's configuration file:

_terraform/main.tf_
```conf
module "myapp-subnet" {
  source = "./modules/subnet"

  env_prefix = var.env_prefix
  avail_zone = var.avail_zone
  subnet_cidr_block = var.subnet_cidr_block
  vpc_id = aws_vpc.myapp-vpc.id
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id
}
```

**Step 5:** Add module output to fix broken references\
At this point the references in the root module to other resources that now have been moved to the `subnet` module (e.g. `subnet_id = aws_subnet.myapp-subnet-1.id` in the `aws_instance.myapp-server` resource) are broken.

In order to fix these references, the child module has to output the required resources and the parrent module has to reference them. So first let the child module output the subnet resource:

_terraform/modules/subnet/outputs.tf_
```conf
output "subnet" {
  value = aws_subnet.myapp-subnet-1
}
```

Now we can reference the output as follows:

_terraform/main.tf_
```conf
resource "aws_instance" "myapp-server" {
  ...
  subnet_id = module.myapp-subnet.subnet.id   # was aws_subnet.myapp-subnet-1.id
  ...
}
```

**Step 6:** Create `webserver` module\
Let's repeat the same steps to extract a `webserver` module responsible for creating an EC2 instance.

- First move the security group "default-sg", the AMI data "latest-amazon-linux-image", the key-pair "ssh-key" and the instance "myapp-server" from the root module's configuration file to the webserver module's configuration file.
- Then extract variables for elements to be passed in by the root module or for elements you think would make sense to be configurable for a module creating an EC2 instance (e.g. the ami name or the path to the entry-script file).

This results in the following files:

_terraform/modules/webserver/main.tf_
```conf
resource "aws_default_security_group" "default-sg" {
  vpc_id = var.vpc_id    # was aws_vpc.myapp-vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ...

  tags = {
    Name = "${var.env_prefix}-default-sg"
  }
}

data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "name"
    values = [var.image_name]    # was "amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ssh-key" {
  key_name = "server-key"
  public_key = file(var.public_key_location)
}

resource "aws_instance" "myapp-server" {
  ami = data.aws_ami.latest-amazon-linux-image.id
  instance_type = var.instance_type

  subnet_id = var.subnet_id    # was module.myapp-subnet.subnet.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone = var.avail_zone

  associate_public_ip_address = true
  key_name = aws_key_pair.ssh-key.key_name

  user_data = file(var.entry_script_file_path)

  tags = {
    Name = "${var.env_prefix}-server"
  }
}
```

_terraform/modules/webserver/variables.tf_
```conf
variable env_prefix {}
variable avail_zone {}
variable my_ip {}
variable instance_type {}
variable public_key_location {}
variable vpc_id {}
variable image_name {}
variable subnet_id {}
variable entry_script_file_path {}
```

**Step 7:** Use the new webserver module\
Now we can reference the new module from within the root module's configuration file:

_terraform/main.tf_
```conf
module "myapp-server" {
  source = "./modules/webserver"
  
  env_prefix = var.env_prefix
  avail_zone = var.avail_zone
  vpc_id = aws_vpc.myapp-vpc.id
  subnet_id = module.myapp-subnet.subnet.id
  my_ip = var.my_ip
  image_name = var.image_name
  public_key_location = var.public_key_location
  instance_type = var.instance_type
  entry_script_file_path = "entry-script.sh"  # note that file paths are relative to the root module
}
```

As we introduced a new variable `image_name` we have to add it to the file _terraform/variables.tf_ and set its value in the file _terraform/terraform.tfvars_:

_terraform/variables.tf_
```conf
variable env_prefix {}
variable avail_zone {}
variable vpc_cidr_block {}
variable subnet_cidr_block {}
variable my_ip {}
variable image_name {}   # <---
variable instance_type {}
variable public_key_location {}
```

_terraform/terraform.tfvars_
```conf
env_prefix = "dev"
avail_zone = "eu-central-1a"
vpc_cidr_block = "10.0.0.0/16"
subnet_cidr_block = "10.0.10.0/24"
my_ip = "31.10.152.229/32"
image_name = "amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"   # <---
instance_type = "t2.micro"
public_key_location = "/Users/fsiegrist/.ssh/id_ed25519.pub"
```

**Step 8:** Fix broken outputs\
And finally we have to adjust the outputs. The references in the root module's _outputs.tf_ file are broken. We have to output the required resources in the child module (webserver) and reference these outputs in the root module (we just keep the output of the EC2's public IP address):

_terraform/modules/webserver/outputs.tf_
```conf
output "instance" {
    value = aws_instance.myapp-server
}
```

_terraform/outputs.tf_
```conf
output "ec2_public_ip" {
    value = module.myapp-server.instance.public_ip
}
```

**Step 9:** Apply the configuration changes\
Whenever a module was created or changed we have to execute `terraform init` in order to reinitialize the working directory. Only then we can execute `terraform apply`.

```sh
terraform init
# Initializing the backend...
# Initializing modules...
# - myapp-server in modules/webserver
# - myapp-subnet in modules/subnet
# 
# Initializing provider plugins...
# - Reusing previous version of hashicorp/aws from the dependency lock file
# - Using previously-installed hashicorp/aws v4.67.0
# 
# Terraform has been successfully initialized!

terraform plan
# module.myapp-server.data.aws_ami.latest-amazon-linux-image: Reading...
# module.myapp-server.data.aws_ami.latest-amazon-linux-image: Read complete after 1s [id=ami-08e415170f52d1657]
# 
# Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
#   + create
# 
# Terraform will perform the following actions:
# 
#   # aws_vpc.myapp-vpc will be created
#   ...
#   # module.myapp-server.aws_default_security_group.default-sg will be created
#   ...
#   # module.myapp-server.aws_instance.myapp-server will be created
#   ...
#   # module.myapp-server.aws_key_pair.ssh-key will be created
#   ...
#   # module.myapp-subnet.aws_default_route_table.main-rtb will be created
#   ...
#   # module.myapp-subnet.aws_internet_gateway.myapp-igw will be created
#   ...
#   # module.myapp-subnet.aws_subnet.myapp-subnet-1 will be created
#   ...
# 
# Plan: 7 to add, 0 to change, 0 to destroy.
# 
# Changes to Outputs:
#   + ec2_public_ip = (known after apply)

terraform apply --auto-approve
# module.myapp-server.aws_key_pair.ssh-key: Creating...
# aws_vpc.myapp-vpc: Creating...
# module.myapp-server.aws_key_pair.ssh-key: Creation complete after 0s [id=server-key]
# aws_vpc.myapp-vpc: Creation complete after 2s [id=vpc-06d768874f8fd7a1e]
# module.myapp-subnet.aws_internet_gateway.myapp-igw: Creating...
# module.myapp-subnet.aws_subnet.myapp-subnet-1: Creating...
# module.myapp-server.aws_default_security_group.default-sg: Creating...
# module.myapp-subnet.aws_internet_gateway.myapp-igw: Creation complete after 0s # [id=igw-038849433c53ae77c]
# module.myapp-subnet.aws_default_route_table.main-rtb: Creating...
# module.myapp-subnet.aws_subnet.myapp-subnet-1: Creation complete after 0s # [id=subnet-0a099f1b5ff742652]
# module.myapp-subnet.aws_default_route_table.main-rtb: Creation complete after 1s # [id=rtb-00643f38eb8d0d375]
# module.myapp-server.aws_default_security_group.default-sg: Creation complete after 1s # [id=sg-0dde6474a1bb17d00]
# module.myapp-server.aws_instance.myapp-server: Creating...
# module.myapp-server.aws_instance.myapp-server: Still creating... [10s elapsed]
# module.myapp-server.aws_instance.myapp-server: Still creating... [20s elapsed]
# module.myapp-server.aws_instance.myapp-server: Creation complete after 22s # [id=i-020f5f1847cd927a2]
# 
# Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
# 
# Outputs:
# 
# ec2_public_ip = "18.156.84.242"
```

**Step 10:** SSH into EC2 instance (optional)\
To check whether the EC2 instance was created successfully, Docker was installed and nginx is running, ssh into the new instance:

```sh
ssh ec2-user@18.156.84.242
docker ps
# CONTAINER ID   IMAGE     COMMAND                  CREATED             STATUS             PORTS                                   NAMES
# ba97d58110bc   nginx     "/docker-entrypoint.…"   About an hour ago   Up About an hour   0.0.0.0:8080->80/tcp, :::8080->80/tcp   serene_leakey
```
