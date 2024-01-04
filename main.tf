terraform {
  cloud {
    organization = "terraform-DamTem"
    workspaces {
      name = "Go-green-mini-project"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-west-2"
}

# CloudWatch Log Group for HTTP errors
resource "aws_cloudwatch_log_group" "http_errors_log_group" {
  name = "/var/log/http_errors"
  retention_in_days = 7
}

# Metric Filter for HTTP errors in CloudWatch Logs
resource "aws_cloudwatch_log_metric_filter" "http_errors_metric_filter" {
  name           = "http_errors_filter"
  pattern        = "400"
  log_group_name = aws_cloudwatch_log_group.http_errors_log_group.name

  metric_transformation {
    name      = "HTTP4xxErrors"
    namespace = "Go-green-web-tierApp"  
    value     = "1"
  }
}

# CloudWatch Alarm to trigger SNS notification for HTTP errors
resource "aws_cloudwatch_metric_alarm" "http_errors_alarm" {
  alarm_name          = "HTTP4xxErrorsAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTP4xxErrors"
  namespace           = "Go-green-web-tierApp"  
  period              = 60  # 60 seconds per minute
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "HTTP 4xx Errors exceed 100 per minute"
  actions_enabled     = true

  alarm_actions = [aws_sns_topic.http_errors_sns_topic.arn]
}

# SNS Topic for HTTP errors notification
resource "aws_sns_topic" "http_errors_sns_topic" {
  name = "HTTPErrorsTopic"
}

# Subscription to SNS Topic (replace with the desired endpoint, like an email address)
resource "aws_sns_topic_subscription" "http_errors_sns_subscription" {
  topic_arn = aws_sns_topic.http_errors_sns_topic.arn
  protocol  = "email"
  endpoint  = "admin@example.com"  
}

# Create an Auto Scaling Group
resource "aws_launch_configuration" "web_launch_config" {
  name_prefix = "web-launch-config"
  image_id = "ami-01450e8988a4e7f44"  # Amazon Linux 2 
  instance_type = "t2.micro"


}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2  # Initial number of instances
  max_size             = 5  # Maximum number of instances
  min_size             = 1  # Minimum number of instances
  launch_configuration = aws_launch_configuration.web_launch_config.id
  vpc_zone_identifier  = ["subnet-0b5b6c780638037c7", "subnet-01ce7e7edf2122e9a"]  
}

# Create an Elastic Load Balancer (ELB)
resource "aws_lb" "web_lb" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-0bf4ff1a0cd309ba1"]  

  enable_deletion_protection = false  # Set to true if you want to enable deletion protection

  enable_cross_zone_load_balancing = true  # Enable cross-zone load balancing

  subnets = ["subnet-0b5b6c780638037c7", "subnet-01ce7e7edf2122e9a"]  
  # Configure listener for HTTP traffic on port 80
#   listener {
#     port     = 80
#     protocol = "HTTP"

#     default_action {
#       target_group_arn = aws_lb_target_group.web_tg.arn
#       type             = "forward"
#     }
#   }
}

# Declare AWS Target Group for Load Balancer
resource "aws_lb_target_group" "web_tg" {
  name        = "web-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "vpc-04445361ffcb055fd"  
}

#Create instances as part of Auto Scaling Group
resource "aws_instance" "web_instance" {
  count         = aws_autoscaling_group.web_asg.desired_capacity
  ami           = "ami-01450e8988a4e7f44"  # Amazon Linux 2 AMI 
  instance_type = "t2.micro"

  vpc_security_group_ids = ["sg-0bf4ff1a0cd309ba1"]  

  tags = {
    Name = "web-instance-${count.index + 1}"
  }
# Add connection block
#   connection {
#     type        = "ssh"
#     user        = "ec2-user"  # or the appropriate user for your AMI
#     private_key = file("/path/to/your/private/key.pem")
#     host        = self.public_ip
#   }
 user_data = <<-EOF
    !/bin/bash -ex

    # Update the system
    sudo dnf -y update

    # Install MySQL Community Server
    sudo dnf -y install https://dev.mysql.com/get/mysql80-community-release-el9-1.noarch.rpm
    sudo dnf -y install mysql-community-server

    # Start and enable MySQL
    sudo systemctl start mysqld
    sudo systemctl enable mysqld

    # Install Apache and PHP
    sudo dnf -y install httpd php

    # Start and enable Apache
    sudo systemctl start httpd
    sudo systemctl enable httpd

    # Navigate to the HTML directory
    cd /var/www/html

    # Download and extract a compressed file
    sudo wget https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/CUR-TF-200-ACACAD/studentdownload/lab-app.tgz
    sudo tar xvfz lab-app.tgz

    # Change ownership of a file
    sudo chown apache:root /var/www/html/rds.conf.php
  EOF
}
