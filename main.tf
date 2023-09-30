terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

    }
  }



  backend "s3" {
    bucket = "js-terraform-bucket"
    key    = "path/to/my/key"
    region = "eu-west-2"
  }
}

data "aws_subnet" "subnet_a" {
  id = "subnet-07817b04f14c3ba83"
}

data "aws_subnet" "subnet_b" {
  id = "subnet-0f5c6a45095190c27"
}

data "aws_subnet" "subnet_c" {
  id = "subnet-04208ac89fa9534a4"
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "dbsubnetgroup"
  subnet_ids = [data.aws_subnet.subnet_a.id, data.aws_subnet.subnet_b.id, data.aws_subnet.subnet_c.id]

  tags = {
    Name = "dbsubnetgroup"
  }
}

resource "aws_db_instance" "rds_app" {
  allocated_storage    = 10
  engine               = "postgres"
  engine_version       = "15.3"
  instance_class       = "db.t3.micro"
  identifier           = "task-listing-app-db"
  db_name              = "taskappdb"
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = true
}

resource "aws_s3_bucket" "task-listing-app-bucket" {
  bucket = "task-listing-app-bucket"

  tags = {
    Name        = "task-listing-app-bucket"
    Environment = "Dockerfile"
  }
}

resource "aws_iam_instance_profile" "task-listing-app-profile" {
  name = "task-listing-app-instance-profile-ec2-instance-profile"
  role = aws_iam_role.task-listing-app-role.name
}

resource "aws_iam_role" "task-listing-app-role" {
  name = "task-listing-app-ec2-instance-role"

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
  role       = aws_iam_role.task-listing-app-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "docker" {
  role       = aws_iam_role.task-listing-app-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "webtier" {
  role       = aws_iam_role.task-listing-app-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.task-listing-app-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


resource "aws_elastic_beanstalk_application" "task-listing-app" {
  name        = "task-listing-app"
  description = "Task listing app"
}



resource "aws_elastic_beanstalk_environment" "task-listing-app-environment" {
  name                = "task-listing-app-environment"
  application         = aws_elastic_beanstalk_application.task-listing-app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.0.1 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.task-listing-app-profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "EC2KeyName"
    value     = "task-listing-app"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.micro"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "singleinstance"
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
  region  = "eu-west-2"
  profile = "terraform-user"
}


resource "aws_ecr_repository" "task-lising-app-ecr" {
  name                 = "taskappecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "task-listing-app-ecr-lifecycle-policy" {
  repository = aws_ecr_repository.task-lising-app-ecr.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire images older than 14 days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}