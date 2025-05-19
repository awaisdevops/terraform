## Demo Project - Configure a Shared Remote State

### Topics of the Demo Project
Configure a Shared Remote State

### Technologies Used
- Terraform
- AWS S3

### Project Description
- Configure Amazon S3 as remote storage for Terraform state

#### Steps to configure Amazon S3 as remote storage for Terraform state
Inside the Terraform configuration file we add a `backend` attribute to the `terraform` block defining the remote AWS S3 state storage:

```conf
terraform {
  required_version = ">= 1.2.0"
  backend "s3" {
    bucket = "my-devops-bootcamp-tfstate-bucket"
    key = "myapp/state.tfstate"
    region = "eu-central-1"
  }
}
```

To use this storage we have to create the bucket on AWS.

#### Steps to create an AWS S3 bucket
- Login to your AWS Management Console and navigate to Services > Storage > S3. The current region automatically switches to "Global".
- Press "Create bucket", enter the bucket name "my-devops-bootcamp-tfstate-bucket" (must be a name which is unique in the global namespace), select your region (eu-central-1), enable Bucket Versioning and leave all the other options unchanged.
- Press "Create bucket".
- Clicking on the newly created bucket opens it, but there are no objects stored yet.

#### Steps to run the pipeline with the modified Terraform configuration
When we commit our changes to the configuration file and thus trigger a new build of the multibranch pipeline, the first version of the remote state file will be creates by Jenkins.

If the `terraform init` command fails because it prompts whether the existing local state should be migrated to the new S3 remote state, you may have to enter the Jenkins workspace and manually delete the local state file:

```sh
ssh root@64.225.104.226
docker exec -it 54ae5b80a7c8 bash
cd /var/jenkins_home/workspace/<pipeline>/terraform
rm terraform.tfstate
rm terraform.tfstate.backup
exit
exit
```

Then you can trigger a new pipeline build via Jenkins UI.

After the pipeline run has completed successfully, we see the state file in our AWS S3 bucket.

Don't forget to destroy the EC2 instance when you don't need it anymore:

```sh
# go to the java-maven-app project folder on your local machine and switch to the terraform folder
terraform init
# Initializing the backend...
# 
# Successfully configured the backend "s3"! Terraform will automatically
# use this backend unless the backend configuration changes.
# ...

terraform state list # <-- connects to the s3 bucket and reads the current state from there
# data.aws_ami.latest-amazon-linux-image
# aws_default_route_table.main-rtb
# aws_default_security_group.default-sg
# aws_instance.myapp-server
# aws_internet_gateway.myapp-igw
# aws_subnet.myapp-subnet-1
# aws_vpc.myapp-vpc

terraform destroy --auto-approve
# ...
# aws_instance.myapp-server: Destruction complete after 41s
# ...

terraform state list
# ---
```

Also remove the S3 bucket. This has to be done via the AWS Management Console. You first have to empty it before you can delete it.