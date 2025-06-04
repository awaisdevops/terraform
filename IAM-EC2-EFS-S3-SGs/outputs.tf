output "vpc_id" {
  description = "The ID of the dedicated VPC."
  value       = aws_vpc.dedicated_vpc.id
}

output "ec2_instance_public_ip" {
  description = "The public IP address of the EC2 instance."
  value       = aws_instance.my_ec2_instance.public_ip
}

output "ec2_instance_private_ip" {
  description = "The private IP address of the EC2 instance."
  value       = aws_instance.my_ec2_instance.private_ip
}

output "efs_file_system_id" {
  description = "The ID of the EFS file system."
  value       = aws_efs_file_system.my_efs.id
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket created."
  value       = aws_s3_bucket.my_s3_bucket.id
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance."
  value       = "ssh -i ${var.private_key_path} ${var.ec2_user}@${aws_instance.my_ec2_instance.public_ip}"
}
