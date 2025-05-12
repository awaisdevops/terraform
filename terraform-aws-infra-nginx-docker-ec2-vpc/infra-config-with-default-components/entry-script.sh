#!/bin/bash
# Use bash shell to interpret this script

sudo yum update -y && sudo yum install -y docker
# Update all installed packages and install Docker non-interactively (-y)

sudo systemctl start docker
# Start the Docker service to enable container management

sudo usermod -aG docker ec2-user
# Add the default EC2 user (ec2-user) to the Docker group to allow running Docker commands without sudo

docker run -p 8080:80 nginx
# Run an Nginx container, mapping host port 8080 to container port 80, making Nginx accessible on port 8080

