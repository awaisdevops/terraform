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
stage('provision server') {
    environment {
        AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
        AWS_SECRET_ACCESS_KEY = credentials('jenkins_aws_secret_access_key')
        TF_VAR_env_prefix = 'test'
    }
    steps {
        script {
            dir('terraform') {
                sh "terraform init"
                sh "terraform apply --auto-approve"
                EC2_PUBLIC_IP = sh(
                    script: "terraform output ec2_public_ip",
                    returnStdout: true
                ).trim()
            }
        }
    }
}
```

## Deploy Stage in Jenkinsfile

```groovy
stage('deploy') {
    environment {
        DOCKER_CREDS = credentials('docker-hub-repo')
    }
    steps {
        script {
            echo "waiting for EC2 server to initialize"
            sleep(time: 90, unit: "SECONDS")

            echo 'deploying docker image to EC2...'
            echo "${EC2_PUBLIC_IP}"

            def shellCmd = "bash ./server-cmds.sh ${IMAGE_NAME} ${DOCKER_CREDS_USR} ${DOCKER_CREDS_PSW}"
            def ec2Instance = "ec2-user@${EC2_PUBLIC_IP}"

            sshagent(['server-ssh-key']) {
                sh "scp -o StrictHostKeyChecking=no server-cmds.sh ${ec2Instance}:/home/ec2-user"
                sh "scp -o StrictHostKeyChecking=no docker-compose.yaml ${ec2Instance}:/home/ec2-user"
                sh "ssh -o StrictHostKeyChecking=no ${ec2Instance} ${shellCmd}"
            }
        }
    }
}
```

## Jenkinsfile

```groovy
#!/usr/bin/env groovy

library identifier: 'jenkins-shared-library@master', retriever: modernSCM(
    [$class: 'GitSCMSource',
     remote: '[https://gitlab.com/nanuchi/jenkins-shared-library.git](https://gitlab.com/nanuchi/jenkins-shared-library.git)',
     credentialsId: 'gitlab-credentials'
    ]
)

pipeline {
    agent any
    tools {
        maven 'Maven'
    }
    environment {
        IMAGE_NAME = 'awaisakram/demo-app:java-maven-2.0'
    }
    stages {
        stage('build app') {
            steps {
                script {
                    echo 'building application jar...'
                    buildJar()
                }
            }
        }
        stage('build image') {
            steps {
                script {
                    echo 'building docker image...'
                    buildImage(env.IMAGE_NAME)
                    dockerLogin()
                    dockerPush(env.IMAGE_NAME)
                }
            }
        }
        stage('provision server') {
            environment {
                AWS_ACCESS_KEY_ID = credentials('jenkins_aws_access_key_id')
                AWS_SECRET_ACCESS_KEY = credentials('jenkins_aws_secret_access_key')
                TF_VAR_env_prefix = 'test'
            }
            steps {
                script {
                    dir('terraform') {
                        sh "terraform init"
                        sh "terraform apply --auto-approve"
                        EC2_PUBLIC_IP = sh(
                            script: "terraform output ec2_public_ip",
                            returnStdout: true
                        ).trim()
                    }
                }
            }
        }
        stage('deploy') {
            environment {
                DOCKER_CREDS = credentials('docker-hub-repo')
            }
            steps {
                script {
                    echo "waiting for EC2 server to initialize"
                    sleep(time: 90, unit: "SECONDS")

                    echo 'deploying docker image to EC2...'
                    echo "${EC2_PUBLIC_IP}"

                    def shellCmd = "bash ./server-cmds.sh ${IMAGE_NAME} ${DOCKER_CREDS_USR} ${DOCKER_CREDS_PSW}"
                    def ec2Instance = "ec2-user@${EC2_PUBLIC_IP}"

                    sshagent(['server-ssh-key']) {
                        sh "scp -o StrictHostKeyChecking=no server-cmds.sh ${ec2Instance}:/home/ec2-user"
                        sh "scp -o StrictHostKeyChecking=no docker-compose.yaml ${ec2Instance}:/home/ec2-user"
                        sh "ssh -o StrictHostKeyChecking=no ${ec2Instance} ${shellCmd}"
                    }
                }
            }
        }
    }
}
```

## License

This project is licensed under the MIT License.
