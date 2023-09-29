terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "jdtfbucket"
    key    = "path/to/my/key"
    region = "eu-west-2"
  }
}

data "aws_subnet" "subnet_a" {
  id = "subnet-0384310cda7f3225b"
}

data "aws_subnet" "subnet_b" {
  id = "subnet-0e606c290592d4005"
}

data "aws_subnet" "subnet_c" {
  id = "subnet-04a8c56d32950f29b"
}

resource "aws_db_subnet_group" "jakedenisesubnetgroup" {
  name       = "jakedenisesubnetgroup"
  subnet_ids = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id, data.aws_subnet.subnet_c.id]

  tags = {
    Name = "jakedenisesubnetgroup"
  }
}

resource "aws_db_instance" "rds_app" {
  allocated_storage    = 10
  engine               = "postgres"
  engine_version       = "15.3"
  instance_class       = "db.m6g.large"
  identifier           = "jakedenise-example-app-prod"
  db_name              = "jakedenisedatabase"
  db_subnet_group_name = aws_db_subnet_group.jakedenisesubnetgroup.name
  username             = "root"
  password             = "password"
  skip_final_snapshot  = true
  publicly_accessible  = true
}

resource "aws_s3_bucket" "jakedenisebucket" {
  bucket = "jakedenisebucket"

  tags = {
    Name        = "jakedenisebucket"
    Environment = "Dockerfile"
  }
}

resource "aws_iam_instance_profile" "jakedeniseprofile" {
  name = "jake-denise-task-listing-app-ec2-instance-profile"
  role = aws_iam_role.jakedeniserole.name
}

resource "aws_iam_role" "jakedeniserole" {
  name = "jake-denise-task-listing-app-ec2-instance-role"

  // Allows the EC2 instances in our EB environment to assume (take on) this 
  // role. 
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.jakedeniserole.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "docker" {
  role       = aws_iam_role.jakedeniserole.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "webtier" {
  role       = aws_iam_role.jakedeniserole.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.jakedeniserole.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


resource "aws_elastic_beanstalk_application" "example_app" {
  name        = "jakedenise-task-listing-app"
  description = "Task listing app"
}



resource "aws_elastic_beanstalk_environment" "example_app_environment" {
  name                = "jakedenise-task-listing-app-environment"
  application         = aws_elastic_beanstalk_application.example_app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.0.1 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.jakedeniseprofile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "EC2KeyName"
    value     = "jakeDeniseTaskApp"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.rds_app.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_DATABASE"
    value     = aws_db_instance.rds_app.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USER"
    value     = aws_db_instance.rds_app.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.rds_app.password
  }
}

provider "aws" {
  region = "eu-west-2"
  profile = "terraform-user"
}


resource "aws_ecr_repository" "app_server_ecr" {
  name                 = "jakedeniseecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

