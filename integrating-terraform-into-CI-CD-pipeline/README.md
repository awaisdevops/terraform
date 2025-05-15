# Integrating Terraform into the CI/CD Pipeline

## Overview

This document describes how to integrate Terraform into an existing CI/CD pipeline. The original pipeline deployed a Docker image to a remote EC2 instance. By adding Terraform, the provisioning of the EC2 instance is automated, creating a fully automated CI/CD workflow.

## Existing CI/CD Setup

The existing setup includes a Java Maven project with a CI/CD pipeline defined in a `Jenkinsfile` using a shared Jenkins library. The pipeline consists of the following stages:

* **Build JAR**: Builds the Java application into a JAR file.
* **Build Docker Image**: Creates a Docker image from the JAR.
* **Push to Docker Registry**: Uploads the Docker image to a registry.
* **Deploy to Remote EC2**: Deploys the Docker image to a manually provisioned EC2 instance.

The deployment process involves:

* Manually creating an EC2 instance via the AWS console.
* Hardcoding the EC2 instance's public IP in the `Jenkinsfile`.
* Using an SSH Agent plugin to copy the Docker Compose file and startup script, and then start Docker containers on the remote instance.

## Terraform Integration Plan

The goal is to automate the EC2 instance provisioning using Terraform by adding a new stage to the pipeline:

#### Provision Infrastructure in the Pipeline

* A new stage named `provision-server` will be added to the pipeline.
* This stage will use Terraform to create a new EC2 instance, eliminating the need for manual creation and hardcoded IP addresses.

#### Key Tasks for Terraform Integration

1.  **Generate an SSH Key Pair**: Required for accessing the EC2 instance via SSH. Terraform will assign this key to the instance.
2.  **Install Terraform in the Jenkins Environment**: Necessary to run `terraform init`, `plan`, and `apply` from within the pipeline.
3.  **Create Terraform Configuration Files**: Stored inside the application repository, ensuring Infrastructure as Code (IaC) lives alongside the application code.
4.  **Update the Jenkinsfile**: Add the new `provision-server` stage before deployment and update the `deploy` stage to use the dynamically retrieved IP of the new EC2 instance.

## Implementation Steps

| Step | Description                                                                 |
| :--- | :-------------------------------------------------------------------------- |
| 1    | Generate an SSH key pair for the EC2 instance                               |
| 2    | Install Terraform inside the Jenkins server                                 |
| 3    | Create and commit Terraform configuration files to the repository            |
| 4    | Modify the Jenkinsfile to add `provision-server` and update the `deploy` stage |

## Create SSH Key Pair

The pipeline runs on a Jenkins server, so the key pair needs to be accessible there. The preferred approach is to:

* Manually create a key pair in AWS.
* Add it to Jenkins as a credential.

#### Using AWS Management Console:

1.  Sign in to the [AWS Console](https://console.aws.amazon.com/ec2).
2.  Navigate to EC2 Dashboard.
3.  In the left sidebar, go to **Network & Security** and click on **Key Pairs**.
4.  Click **Create key pair**.
5.  Set the following:

    * **Name**: Choose a recognizable name (e.g., `jenkins-key`).
    * **Key pair type**: RSA (recommended).
    * **Private key file format**: `.pem` (for Linux/macOS) or `.ppk` (for Windows with PuTTY).
6.  Click **Create key pair**.
7.  Download the private key file and store it securely.

#### Creating Jenkins Credentials:

1.  Open Jenkins.
2.  Go to **Manage Jenkins** \> **Credentials**.
3.  Select or create a domain.
4.  Click **Add Credentials**.
5.  Set the following:

    * **Kind**: SSH Username with private key.
    * **Scope**: Global.
    * **Username**: `ec2-user` (or `ubuntu`).
    * **Private Key**: Enter directly and paste the contents of the `.pem` file.
    * Leave **Passphrase** blank unless needed.
    * (Optional) Set **ID**: `aws-ec2-key`.
    * **Description**: EC2 Key for Jenkins.
6.  Click **OK**.

## Install Terraform on Jenkins Server

```bash
sudo apt update && sudo apt upgrade -y                                    # Update and upgrade system packages
sudo apt install -y gnupg software-properties-common curl              # Install required dependencies
curl -fsSL [https://apt.releases.hashicorp.com/gpg](https://apt.releases.hashicorp.com/gpg) | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg  # Add HashiCorp GPG key
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] [https://apt.releases.hashicorp.com](https://apt.releases.hashicorp.com) $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list                       # Add HashiCorp repository
sudo apt update                                                         # Refresh package list
sudo apt install terraform -y                                           # Install Terraform
terraform -version                                                      # Verify Terraform installation
````

## Terraform Configuration Files

Create a `terraform` folder in the project containing Terraform configuration files to deploy an AWS EC2 instance. The configuration should reference the existing AWS key pair and include an entry script to install Docker and Docker Compose on the instance. Variables in the Terraform files are parameterized for overrides from the CI/CD pipeline. Outputs should include the instance’s public IP.

## Provision Stage in Jenkinsfile

```groovy
#!/usr/bin/env groovy
# Specifies the interpreter for the script

library identifier: 'jenkins-shared-library@master', retriever: modernSCM(
    [$class: 'GitSCMSource',
     remote: '[https://gitlab.com/nanuchi/jenkins-shared-library.git](https://gitlab.com/nanuchi/jenkins-shared-library.git)',
     credentialsId: 'gitlab-credentials'
    ]
)
# Defines the Jenkins shared library to be used

pipeline {
    # Defines the pipeline block
    agent any
    # Executes the pipeline on any available Jenkins agent
    tools {
        # Specifies required tools
        maven 'Maven'
        # Requires a Maven installation named 'Maven' to be configured in Jenkins
    }
    environment {
        # Defines environment variables for the pipeline
        IMAGE_NAME = 'awaisakram/demo-app:java-maven-2.0'
        # Sets the Docker image name
    }
    stages {
        # Defines the stages of the pipeline
        stage('build app') {
            # Stage for building the application
            steps {
                # Defines the steps within the 'build app' stage
                script {
                    # Executes a Groovy script block
                    echo 'building application jar...'
                    # Prints a message to the console
                    buildJar()
                    # Calls a function (presumably defined in the shared library) to build the JAR file
                }
            }
        }
        stage('build image') {
            # Stage for building the Docker image
            steps {
                # Defines the steps within the 'build image' stage
                script {
                    # Executes a Groovy script block
                    echo 'building docker image...'
                    # Prints a message to the console
                    buildImage(env.IMAGE_NAME)
                    # Calls a function to build the Docker image using the defined IMAGE_NAME
                    dockerLogin()
                    # Calls a function to log in to the Docker registry
                    dockerPush(env.IMAGE_NAME)
                    # Calls a function to push the Docker image to the registry
                }
            }
        }
        stage('provision server') {
            # Stage for provisioning the infrastructure (EC2 server)
            environment {
                # Defines environment variables specific to this stage
                AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
                # Retrieves AWS access key from Jenkins credentials with the ID 'jenkins_aws_access_key_id'
                AWS_SECRET_ACCESS_KEY = credentials('jenkins_aws_secret_access_key')
                # Retrieves AWS secret access key from Jenkins credentials with the ID 'jenkins_aws_secret_access_key'
                TF_VAR_env_prefix = 'test'
                # Sets a Terraform variable 'env_prefix' to 'test'
            }
            steps {
                # Defines the steps within the 'provision server' stage
                script {
                    # Executes a Groovy script block
                    dir('terraform') {
                        # Changes the current directory to 'terraform'
                        sh "terraform init"
                        # Executes the 'terraform init' command
                        sh "terraform apply --auto-approve"
                        # Executes the 'terraform apply --auto-approve' command
                        EC2_PUBLIC_IP = sh(
                            script: "terraform output ec2_public_ip",
                            returnStdout: true
                        ).trim()
                        # Executes 'terraform output ec2_public_ip', captures the output, and removes leading/trailing whitespace
                    }
                }
            }
        }
        stage('deploy') {
            # Stage for deploying the application to the provisioned server
            environment {
                # Defines environment variables specific to this stage
                DOCKER_CREDS = credentials('docker-hub-repo')
                # Retrieves Docker Hub credentials from Jenkins with the ID 'docker-hub-repo'
            }
            steps {
                # Defines the steps within the 'deploy' stage
                script {
                    # Executes a Groovy script block
                    echo "waiting for EC2 server to initialize"
                    # Prints a message to the console
                    sleep(time: 90, unit: "SECONDS")
                    # Pauses the pipeline execution for 90 seconds

                    echo 'deploying docker image to EC2...'
                    # Prints a message to the console
                    echo "${EC2_PUBLIC_IP}"
                    # Prints the dynamically obtained EC2 public IP

                    def shellCmd = "bash ./server-cmds.sh ${IMAGE_NAME} ${DOCKER_CREDS_USR} ${DOCKER_CREDS_PSW}"
                    # Defines a shell command to be executed on the remote server, using environment variables
                    def ec2Instance = "ec2-user@${EC2_PUBLIC_IP}"
                    # Defines the SSH connection string for the EC2 instance

                    sshagent(['server-ssh-key']) {
                        # Executes commands within an SSH agent context using the credential with ID 'server-ssh-key'
                        sh "scp -o StrictHostKeyChecking=no server-cmds.sh ${ec2Instance}:/home/ec2-user"
                        # Securely copies the 'server-cmds.sh' script to the remote EC2 instance
                        sh "scp -o StrictHostKeyChecking=no docker-compose.yaml ${ec2Instance}:/home/ec2-user"
                        # Securely copies the 'docker-compose.yaml' file to the remote EC2 instance
                        sh "ssh -o StrictHostKeyChecking=no ${ec2Instance} ${shellCmd}"
                        # Executes the defined shell command on the remote EC2 instance via SSH
                    }
                }
            }
        }
    }
}
```
```

## License

This project is licensed under the MIT License.
