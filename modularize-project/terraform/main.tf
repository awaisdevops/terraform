resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

module "myapp-subnet" {
  source = "./modules/subnet"

  env_prefix = var.env_prefix
  avail_zone = var.avail_zone
  subnet_cidr_block = var.subnet_cidr_block
  vpc_id = aws_vpc.myapp-vpc.id
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id
}

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
  entry_script_file_path = "entry-script.sh"
}
