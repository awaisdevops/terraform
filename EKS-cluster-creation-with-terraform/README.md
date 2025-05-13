# EKS Cluster Creation with Terraform

---

This project demonstrates how to automate the creation and management of an AWS EKS (Elastic Kubernetes Service) cluster using Terraform. While setting up an EKS cluster manually via the AWS Management Console or CLI involves many complex steps and configurations, Terraform simplifies and streamlines this process.

## By using Terraform, you can:

- Automate EKS cluster provisioning (control plane, worker nodes, VPC, subnets, etc.)
- Easily replicate environments (dev, test, prod) with consistent configuration
- Track and manage infrastructure changes through version-controlled code
- Efficiently clean up resources when no longer needed

This approach ensures repeatability, transparency, and efficiency, making it easier to collaborate and manage Kubernetes clusters on AWS at scale.

The Terraform configuration in this repository will guide you through creating all necessary components—control plane, worker nodes, VPC, and networking—following best practices for high availability and reliability.

---

## VPC Creation

We'll create an AWS VPC tailored for an EKS cluster using Terraform. It leverages a community Terraform module to create a best-practice network architecture, including public and private subnets across multiple availability zones, route tables, and gateways. The configuration dynamically discovers availability zones and uses variables for flexible, reusable settings. Resources are properly tagged to integrate seamlessly with Kubernetes and AWS services, enabling features like load balancer provisioning and NAT gateways. This approach simplifies and standardizes VPC creation, ensuring a robust and production-ready environment for deploying EKS clusters.

---

## EKS Cluster and Worker Nodes

This section covers how to provision an EKS cluster on AWS using the official Terraform EKS module. The configuration defines essential parameters such as the cluster name, Kubernetes version, VPC ID, and private subnets for secure workload placement. Worker nodes are set up as self-managed EC2 instances, with flexible options for instance types and scaling. The setup leverages Terraform modules and outputs to ensure reusable, maintainable infrastructure code. By automating cluster creation and node management, this approach streamlines EKS deployments and makes it easy to customize, replicate, and manage Kubernetes clusters in AWS environments.

---

## Authenticate with K8s Cluster

This section explains how to configure the Kubernetes provider in Terraform to connect securely to your newly created EKS cluster. By dynamically retrieving the cluster endpoint, authentication token, and certificate authority data from AWS, the provider is set up to authenticate and manage Kubernetes resources within the cluster. The process leverages Terraform modules for VPC and EKS, which handle the creation of all necessary infrastructure and dependencies in the background. This modular approach simplifies cluster provisioning, ensures secure access, and reduces manual configuration, allowing you to manage and deploy Kubernetes resources efficiently through Terraform.

---

## Deploy Nginx-App into our Cluster

Amazon EKS is a managed Kubernetes service that provides a highly available, scalable control plane distributed across multiple Availability Zones, running Kubernetes API servers and etcd instances managed by AWS. Worker nodes run within your AWS account inside a VPC and connect securely to the control plane to run containerized applications. EKS automates control plane management, including scaling, patching, and failover, while nodes can be self-managed or managed via node groups. This architecture ensures resilient, secure, and scalable Kubernetes clusters integrated with AWS networking, IAM, and load balancing services.

---

## authenticate kubectll with our cluster

we need to authenticate kubectll with our cluster. for that we must have installed  
1: AWS cli  
2: kubectl  
3: aws-iam-authenticator  

```bash
-->> aws eks update-kubeconfig --name myapp-eks-cluster --region eu-west-2
-->> aws eks update-kubeconfig --<cluster-name> --region <region-name-where-eks-cluster-is-setup>
````

> with this command, we'll first get authenticated with AWS then our EKS cluster

---

## ➤ vim vpc.tf

```hcl
provider "aws" {
    region = "******"
    access_key = "*************"
    secret_key = "********************************"
}

variable vpc_cidr_block {}
variable private_subnet_cidr_blocks {} 
variable public_subnet_cidr_blocks {}

data "aws_availability_zones" "azs" {}

module "myapp-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.18.1"

  name = "myapp-vpc"
  cidr = var.vpc_cidr_block
  private_subnets = var.private_subnet_cidr_blocks 
  public_subnets = var.public_subnet_cidr_blocks

  azs = data.aws_availability_zones.azs.names
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/myapp-eks-cluster" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/myapp-eks-cluster" = "shared"
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/myapp-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb" = 1
  }
}
```

---

## ➤ vim terraform.tfvars

```hcl
vpc_cidr_block = "10.0.0.0/16"
private_subnet_cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"] 
public_subnet_cidr_blocks = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
```

---

## ➤ vim eks-cluster.tf

```hcl
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
        launch_template_name = "worker-group-1-template"
    },
    {
        instance_type = "t2.medium"
        name = "worker-group-2"
        asg_desired_capacity = 1
        launch_template_name = "worker-group-2-template"
    },
  ]
}
```

---

## License

This project is licensed under the [MIT License](LICENSE).


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

### for debuggin in TF
    
    export TF_LOG=TRACE    
