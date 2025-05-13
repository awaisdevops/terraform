provider "kubernetes" {
  load_config_file = "false"
  host = data.aws_eks_cluster.myapp-cluster.endpoint
  token = data.aws_eks_cluster_auth.myapp-cluster.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.myapp-cluster.certificate_authority.0.data)
}

data "aws_eks_cluster" "myapp-cluster" {
  name = module.eks.cluster_id 
}

data "aws_eks_cluster_auth" "myapp-cluster" {
  name = module.eks.cluster_id
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.33.1"

  cluster_name = "myapp-eks-cluster"
  cluster_version = null
  vpc_id = module.myapp-vpc.vpc_id

  subnet_ids  = module.myapp-vpc.private_subnets

  tags = {
    environment = "development"
    application = "myapp"
  }

  self_managed_node_groups = [
    {
        instance_type = "t2.small"
        name = "worker-group-1"
        asg_desired_capacity = 2
	launch_template_name = "worker-group-1-template"  # Add this line
    },

    {
        instance_type = "t2.medium"
        name = "worker-group-2"
        asg_desired_capacity = 1
	launch_template_name = "worker-group-2-template"  # Add this line
    },
  ]
}
