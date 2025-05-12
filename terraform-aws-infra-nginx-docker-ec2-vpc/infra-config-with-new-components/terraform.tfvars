vpc_cidr_block = "10.0.0.0/16"           # CIDR block for the VPC, defines the IP address range for the network
subnet_cidr_block = "10.0.10.0/24"       # CIDR block for the subnet within the VPC
avail_zone = "ap-northeast-2c"            # Availability zone where resources will be deployed (Seoul region)
env_prefix = "dev"                        # Environment prefix used for naming/tagging resources (e.g., dev, prod)
my_ip = "110.93.205.18/32"                # Your public IP address with mask, used for restricting SSH access
instance_type = "t2.micro"                 # EC2 instance type specifying hardware configuration
public_key_location = "/home/machine/.ssh/id_rsa.pub"  # File path to your public SSH key for EC2 access

