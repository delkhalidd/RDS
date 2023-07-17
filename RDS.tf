# Part A: VPC with 2 public and 2 private subnets

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create an Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create a route table for public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
}
resource "aws_route" "route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_igw.id
  depends_on = [
    aws_internet_gateway.my_igw
  ]

}

# Create two public subnets (one in each availability zone)
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

# Associate the public subnets with the route table
resource "aws_route_table_association" "public_subnet_association_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create two private subnets (one in each availability zone)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

# Part B: EC2 instances

# Create an Auto Scaling Group with at least 2 EC2 instances (one in each public subnet)
resource "aws_launch_configuration" "my_lc" {
  image_id        = "ami-0715c1897453cabd1"
   instance_type   = "t2.medium" 
  key_name        = "test2"
  security_groups = [aws_security_group.web_servers.id]
  user_data       = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo dnf install mariadb105-server httpd -y
    sudo systemctl start httpd
    sudo systemctl enable httpd
    sudo echo "Welcome to Amazon Linux" >  /var/www/html/index.html
  EOF
}


resource "aws_instance" "bastion_host" {
  ami                         = "ami-0715c1897453cabd1" 
  instance_type               = "t2.medium"
  key_name                    = "test2"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.public_subnet_2.id
  security_groups             = [aws_security_group.bastion_sec.id]

  

}

resource "aws_security_group" "bastion_sec" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "my_asg" {
  launch_configuration = aws_launch_configuration.my_lc.name
  min_size             = 2
  max_size             = 2
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  target_group_arns    = [aws_lb_target_group.my_target_group.arn]

}


output "bastion_public_ip" {
  value = aws_instance.bastion_host.public_ip
}

# Create a security group for the web servers
resource "aws_security_group" "web_servers" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.bastion_host.public_ip}/32"]
  }
   ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a security group for the web servers
resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
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
}
# Create an Application Load Balancer
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups    = [aws_security_group.alb.id]
  internal           = false
  load_balancer_type = "application"
}

# Create a target group
resource "aws_lb_target_group" "my_target_group" {
  name        = "my-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
  target_type = "instance"
  health_check {
    path = "/"
  }
}
/*# Attach the instances to the target group
resource "aws_lb_target_group_attachment" "my_target_group_attachment" {
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = aws_autoscaling_group.my_asg.id
  port             = 80
}*/

resource "aws_autoscaling_attachment" "my_target_group_attachment" {
  autoscaling_group_name = aws_autoscaling_group.my_asg.id
  lb_target_group_arn    = aws_lb_target_group.my_target_group.arn
}

resource "aws_lb_listener" "alb_listner" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}



# Part C: RDS

# Create an RDS subnet group using the private subnets
resource "aws_db_subnet_group" "my_db_subnet_group" {
  name       = "my-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

#Create an RDS instance in the RDS subnet group
resource "aws_db_instance" "my_db_instance" {
  engine                 = "mariadb"
  engine_version         = "10.6.10"
  instance_class         = "db.t2.micro"
  #name                   = "mydbinstance"
  username               = "admin"
  password               = "password123"
  allocated_storage      = 20
  storage_type           = "gp2"
  db_subnet_group_name   = aws_db_subnet_group.my_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.web_servers.id]
}