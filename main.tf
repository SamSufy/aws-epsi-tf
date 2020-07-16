# AWS Provider

provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
}

#--------------------------------------- RESEAU ----------------------------------------

# Create VPC
resource "aws_vpc" "vpc_tf" {
  cidr_block = "10.10.0.0/16"
  tags = {
    name = "vpc_tf"
  }
}

# Create subnet
resource "aws_subnet" "subnet_1_tf" {
  cidr_block = "10.10.1.0/24"
  vpc_id = aws_vpc.vpc_tf.id
  tags = {
    Name = "subnet_1_tf"
   }
}

resource "aws_subnet" "subnet_2_tf" {
  cidr_block = "10.10.2.0/24"
  vpc_id = aws_vpc.vpc_tf.id
  tags = {
    Name = "subnet_2_tf"
   }
}

  # Create gateway
  resource "aws_internet_gateway" "igw_tf" {
  vpc_id = aws_vpc.vpc_tf.id

  tags = {
    Name = "igw_tf"
  }
}

# Create routetable
resource "aws_route_table" "routetable_tf" {
  vpc_id = aws_vpc.vpc_tf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_tf.id
  }

  tags = {
    Name = "routetable_tf"
  }
}

#Create association route table
resource "aws_route_table_association" "routetableassociation" {
  subnet_id      = aws_subnet.subnet_1_tf.id
  route_table_id = aws_route_table.routetable_tf.id
}

#--------------------------------------- END RESEAU --------------------------------------------

#Create clé RSA 4096
resource "tls_private_key" "key_tf" {
  algorithm   = "RSA"
  rsa_bits = "4096"
}

resource "aws_key_pair" "ec2-key-tf" {
  key_name   = "ec2-key-tf"
  public_key = tls_private_key.key_tf.public_key_openssh
}

#--------------------------------------- INSTANCE ----------------------------------------------

#Create EC2
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

/*resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public-a.id
  key_name      = aws_key_pair.deployer.id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.allow_httpandssh.id]
  user_data     = file("${path.module}/postinstall.sh")

  tags = {
    Name = "HelloWorld"
  }
}

output "public-ip" {
  value = aws_instance.web.public_ip
}


//AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical 
}

output "ami-value" {
    value = data.aws_ami.ubuntu.image_id
}*/

# - - - - - - - - - - - - - - - - - - -  LB  - - - - - - - - - - - - - - - - - - - - - - - - - -

#Create loadbalancer
resource "aws_lb" "alb-tf" {
  name               = "alb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = ["aws_subnet.subnet_1_tf.id", "aws_subnet.subnet_2_tf.id"]
}

#Create lb target group
resource "aws_lb_target_group" "lb-target-group-tf" {
  name     = "lb-target-group-tf"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_tf.id
}

#Create lb listner
resource "aws_lb_listener" "alb_listner_tf" {
  load_balancer_arn = aws_lb.alb-tf.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb-target-group-tf.arn
  }
}

##### END LB #####

##### ASG #####

#Auto-scalling-group
resource "aws_placement_group" "asg_placement_group_tf" {
  name     = "asg_placement_group_tf"
  strategy = "cluster"
}

resource "aws_autoscaling_group" "asg_tf" {
  name                      = "asg_tf"
  max_size                  = 3
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = true
  placement_group           = aws_placement_group.asg_placement_group_tf.id
  launch_configuration      = aws_launch_configuration.launch_configuration_tf.name
  vpc_zone_identifier       = aws_subnet.subnet_1_tf.id

  initial_lifecycle_hook {
    name                 = "asg_lifecycle_tf"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  }

  timeouts {
    delete = "5m"
  }
}

resource "aws_autoscaling_attachment" "asg_attachment_tf" {
  autoscaling_group_name = aws_autoscaling_group.asg_tf.id
  alb_target_group_arn   = aws_alb_target_group.lb-target-group-tf.arn
}

#Create LAUNCH CONFIGURATION
resource "aws_launch_configuration" "launch_configuration_tf" {
  image_id = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  security_groups = aws_security_group.allow_http.id
  user_data = file("${path.module}/post_install.sh")
}

# - - - - - - - - - - - - - - - - - - -  END ASG  - - - - - - - - - - - - - - - - - - - - - - - 

#--------------------------------------- END INSTANCE ------------------------------------------

#--------------------------------------- SECURITY GROUP ----------------------------------------

resource "aws_security_group" "allow_http" {
  name        = "allow_http_from_any"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.vpc_tf.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_security_group" "allow_ssh_vpc" {
  name        = "allow_ssh_from_vpc"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.vpc_tf.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc_tf.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh_vpc"
  }
}

#--------------------------------------- END SECURITY GROUP ------------------------------------

#OUTPUT

/*output "private-key" {
    value = tls_private_key.pkey.private_key_pem
}*/

/*output "public-ip" {
  value = aws_instance.web.public_ip
}*/

