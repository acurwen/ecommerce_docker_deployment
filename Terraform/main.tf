#################
# PROVIDER BLOCK #
##################

provider "aws" {
  access_key = var.aws_access_key          # Replace with your AWS access key ID (leave empty if using IAM roles or env vars)
  secret_key = var.aws_secret_key          # Replace with your AWS secret access key (leave empty if using IAM roles or env vars)
  region     = var.region # Specify the AWS region where resources will be created (e.g., us-east-1, us-west-2)
}

#################
# CUSTOM VPC #
##################

resource "aws_vpc" "customvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "wl6vpc" 
  }
}


# Referencing default VPC
data "aws_vpc" "default" {
  default = true
  
}

###########################
# VPC PEERING CONNECTION #
###########################
resource "aws_vpc_peering_connection" "peer" {
  peer_vpc_id   = aws_vpc.customvpc.id
  vpc_id        = data.aws_vpc.default.id
  auto_accept   = true
}

########################
# UPDATING DEFAULT VPC #
########################

# # Accessing the default route table of the default VPC - Don't need just gonna hard code in the one i see in aws
# data "aws_route_table" "default" {
#   vpc_id = data.aws_vpc.default.id
# }

# Add a route for VPC peering to the default route table
resource "aws_route" "vpc_peering_route" {
  route_table_id            = "rtb-03fe5d7032b7a8714"
  destination_cidr_block    = aws_vpc.customvpc.cidr_block  
  vpc_peering_connection_id  = aws_vpc_peering_connection.peer.id
}


####################
# Internet Gateway #
####################
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.customvpc.id

  tags = {
    Name = "Internet_Gateway"
  }
}

####################
# NAT Gateway 1 #
####################
resource "aws_nat_gateway" "nat1" {
  allocation_id = aws_eip.elastic1.id
  subnet_id     = aws_subnet.pub_sub1.id 

  tags = {
    Name = "NAT_Gateway1" 
  }
   # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.ig]
}

####################
# Elastic IP 1 #
####################

resource "aws_eip" "elastic1" {
  domain   = "vpc"

  tags = {
    Name = "elastic1_ip"
  }
}

####################
# NAT Gateway 2 #
####################
resource "aws_nat_gateway" "nat2" {
  allocation_id = aws_eip.elastic2.id
  subnet_id     = aws_subnet.pub_sub2.id 

  tags = {
    Name = "NAT_Gateway2" 
  }
   # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.ig]
}

####################
# Elastic IP 2 #
####################

resource "aws_eip" "elastic2" {
  domain   = "vpc"

  tags = {
    Name = "elastic2_ip"
  }
}

##############################
# APPLICATION LOAD BALANCER # helps distribute incoming network traffic across multiple EC2 instances
##############################

resource "aws_lb" "app_lb" {
  name               = "applb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.sg_for_lb.id] #Security group controlling inbound/outbound traffic for the ALB.
  subnets            = [aws_subnet.pub_sub1.id, aws_subnet.pub_sub2.id] #List of public subnets (one in each AZ) where the ALB should reside

  enable_deletion_protection = false
    tags = {
    Name = "App Load Balancer"
   }
}

################
# TARGET GROUP # defines the destination for the ALB’s traffic
################

resource "aws_lb_target_group" "mytg" {
  name     = "my-target-group"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.customvpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    #matcher             = "200"  # Expect a 200 OK response
  }
   tags = {
    Name = "my-target-group"
  }

}

##############################
# TARGET GROUP ATTACHMENTS #
##############################

# Target Group Attachment for each EC2 instance
resource "aws_lb_target_group_attachment" "alb_tg_attachment-1" {
  target_group_arn = aws_lb_target_group.mytg.arn
  target_id        = aws_instance.bastion1.id  # Replace with your EC2 instance ID
  port             = 3000  # Matches the target group port
}

resource "aws_lb_target_group_attachment" "alb_tg_attachment-2" {
  target_group_arn = aws_lb_target_group.mytg.arn
  target_id        = aws_instance.bastion2.id  # Replace with your EC2 instance ID
  port             = 3000  # Matches the target group port
}


#################
# ALB LISTENER # sets up the rules for how incoming traffic to the load balancer should be forwarded to the target group
#################

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mytg.arn
  }
}

##################################################
# SECURITY GROUP FOR APPLICATION LOAD BALANCER #
##################################################
resource "aws_security_group" "sg_for_lb" {
  name   = "sg_app_balancer"
  vpc_id = aws_vpc.customvpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_app_balancer"
  }
}

####################
# Public Subnet 1 #
####################
resource "aws_subnet" "pub_sub1" {
  vpc_id     = aws_vpc.customvpc.id
  cidr_block = "10.0.16.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "pub_sub1" 
  }
}
#############################
# Public Route Table - Main #
#############################
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.customvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig.id
  }
  route {
    cidr_block                = data.aws_vpc.default.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }
  
  tags = {
    Name = "pub_rt_main" 
  }
}

###############################################################
# Public Route Table - Main - Association to Public Subnet 1 #
###############################################################
resource "aws_route_table_association" "pub_rt_assc1" {
  subnet_id      = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub_rt.id


}

####################
# Public Subnet 2 #
####################
resource "aws_subnet" "pub_sub2" {
  vpc_id     = aws_vpc.customvpc.id
  cidr_block = "10.0.32.0/24" 
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "pub_sub2" 
  }
}

###############################################################
# Public Route Table - Main - Association to Public Subnet 2 #
###############################################################
resource "aws_route_table_association" "pub_rt_assc2" {
  subnet_id      = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.pub_rt.id

}


####################
# Private Subnet 1 #
####################
resource "aws_subnet" "priv_sub1" {
  vpc_id     = aws_vpc.customvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "priv_sub1"
  }
}
#############################
# Private Route Table 1 #
#############################
resource "aws_route_table" "priv_rt1" {
  vpc_id = aws_vpc.customvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat1.id
  }

  route {
    cidr_block                = data.aws_vpc.default.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }

  tags = {
    Name = "priv_rt1" 
  }
}

#############################################################
# Private Route Table 1 Association to Private Subnet 1 #
#############################################################
resource "aws_route_table_association" "pri_rt_assc1" {
  subnet_id      = aws_subnet.priv_sub1.id
  route_table_id = aws_route_table.priv_rt1.id

}

####################
# Private Subnet 2 #
####################
resource "aws_subnet" "priv_sub2" {
  vpc_id     = aws_vpc.customvpc.id
  cidr_block = "10.0.0.0/24" 
  availability_zone = "us-east-1b"

  tags = {
    Name = "priv_sub2"
  }
}
#############################
# Private Route Table 2 #
#############################
resource "aws_route_table" "priv_rt2" {
  vpc_id = aws_vpc.customvpc.id

  route {
    cidr_block = "0.0.0.0/0" ## CHECK
    gateway_id = aws_nat_gateway.nat2.id
  }

  route {
    cidr_block                = data.aws_vpc.default.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  }

  tags = {
    Name = "priv_rt2" 
  }
}

#############################################################
# Private Route Table 2 Association to Private Subnet 2 #
#############################################################
resource "aws_route_table_association" "pri_rt_assc2" {
  subnet_id      = aws_subnet.priv_sub2.id
  route_table_id = aws_route_table.priv_rt2.id

}

#########################
# KEY PAIRS FOR ALL EC2S
#########################

resource "tls_private_key" "ecommkey" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "ecommkey" {
  key_name   = "ecommkey"
  public_key = tls_private_key.ecommkey.public_key_openssh
}

output "frontback_private_key" {
  value     = tls_private_key.ecommkey.private_key_pem
  sensitive = true
}

# #################################
# # KEY PAIR 2 FOR FRONT/BACK EC2 #2 #
# #################################

# resource "tls_private_key" "frontback_key2" {
#   algorithm = "RSA"
#   rsa_bits  = 2048
# }

# resource "aws_key_pair" "frontback_key2" {
#   key_name   = "frontback-key2"
#   public_key = tls_private_key.frontback_key2.public_key_openssh
# }

# output "frontback_private_key2" {
#   value     = tls_private_key.frontback_key2.private_key_pem
#   sensitive = false
# }


######################################
# SECURITY GROUP FOR BOTH BASTION EC2s #
######################################

resource "aws_security_group" "sg_bastion" { #name that terraform recognizes
  name        = "sg_bastion" #name that will show up on AWS
  description = "Security Group For Both Bastion EC2s"
 
  vpc_id = aws_vpc.customvpc.id
  # Ingress rules: Define inbound traffic that is allowed.Allow SSH traffic and HTTP traffic on port 8080 from any IP address (use with caution)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # allowing all traffic
  }
  # ingress {
  #   from_port   = 3000
  #   to_port     = 3000
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  #  ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }
  # Egress rules: Define outbound traffic that is allowed. The below configuration allows all outbound traffic from the instance.
  egress {
    from_port   = 0                                     # Allow all outbound traffic (from port 0 to any port)
    to_port     = 0
    protocol    = "-1"                                  # "-1" means all protocols
    cidr_blocks = ["0.0.0.0/0"]                         # Allow traffic to any IP address
  }

  # Tags for the security group
  tags = {
    "Name"      = "sg_bastion_main"                          # Name tag for the security group
    "Terraform" = "true"                                # Custom tag to indicate this SG was created with Terraform
  }
}

#################
# BASTION 1 EC2 #
##################
resource "aws_instance" "bastion1" {

  ami               = "ami-0866a3c8686eaeeba"                                           
  instance_type     = var.instance_type  

  subnet_id = aws_subnet.pub_sub1.id
  vpc_security_group_ids = [aws_security_group.sg_ecomm_app.id]   

  key_name          = "ecommkey"               

  user_data         = <<-EOF
    #!/bin/bash
    # Redirect stdout and stderr to a log file
    exec > /var/log/user-data.log 2>&1
    echo "${file("./public_key.txt")}" >> /home/ubuntu/.ssh/authorized_keys
  EOF

  tags = {
    "Name" = "ecommerce_bastion_az1"  
    "Terraform" = "true"       
  }

}

output "bastion1_public_ip1" {
  value = aws_instance.bastion1.public_ip # Display the public IP address of the EC2 instance after creation.
}

output "bastion1_private_ip1" {
  value = aws_instance.bastion1.private_ip # Display the private IP address of the EC2 instance after creation.
}

#################
# BASTION 2 EC2 #
##################
resource "aws_instance" "bastion2" {

  ami               = "ami-0866a3c8686eaeeba"                                        
  instance_type     = var.instance_type      

  subnet_id = aws_subnet.pub_sub2.id
  vpc_security_group_ids = [aws_security_group.sg_ecomm_app.id]   

  key_name          = "ecommkey"               

  user_data         = <<-EOF
    #!/bin/bash
    # Redirect stdout and stderr to a log file
    exec > /var/log/user-data.log 2>&1
    echo "${file("./public_key.txt")}" >> /home/ubuntu/.ssh/authorized_keys
  EOF

  tags = {
    "Name" = "ecommerce_bastion_az2" 
    "Terraform" = "true"        
  }
}

output "bastion2_public_ip2" {
  value = aws_instance.bastion2.public_ip # Display the public IP address of the EC2 instance after creation.
}

output "bastion2_private_ip2" {
  value = aws_instance.bastion2.private_ip # Display the private IP address of the EC2 instance after creation.
}


##############################################
# SECURITY GROUP FOR BOTH ECOMMERCE APP EC2S #
##############################################

resource "aws_security_group" "sg_ecomm_app" { # name that terraform recognizes
  name        = "sg_ecomm_app" # name that will show up on AWS
  description = "Security Group for Ecommerce App EC2s"
 
  vpc_id = aws_vpc.customvpc.id
  # Ingress rules: Define inbound traffic that is allowed. 
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"] # allowing IPs only from public subnet (RIGHT?)
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    description = "Node"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  ingress {
    description = "Node Exporter"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  ingress {
    description = "PostgresSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  # Egress rules: Define outbound traffic that is allowed. The below configuration allows all outbound traffic from the instance.
  egress {
    from_port   = 0                                     # Allow all outbound traffic (from port 0 to any port)
    to_port     = 0
    protocol    = "-1"                                  # "-1" means all protocols
    cidr_blocks = ["0.0.0.0/0"]                         # Allow traffic to any IP address
  }

  # Tags for the security group
  tags = {
    "Name"      = "sg_ecomm_app"                          # Name tag for the security group
    "Terraform" = "true"                                # Custom tag to indicate this SG was created with Terraform
  }
}

######################################
# SECURITY GROUP FOR ECOMMERCE APP 2 #
######################################

# resource "aws_security_group" "sg_ecomm_app2" { #name that terraform recognizes
#   name        = "sg_ecomm_app2" #name that will show up on AWS
#   description = "Port 22 for SSH, Port 8000 for Django and Port 9100 for Node Exporter"
 
#   vpc_id = aws_vpc.customvpc.id
#   # Ingress rules: Define inbound traffic that is allowed.Allow SSH traffic and HTTP traffic on port 8080 from any IP address (use with caution)
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["10.0.1.0/24"] # allowing IPs only from public subnet (RIGHT?)
#   }
#   ingress {
#     from_port   = 8000
#     to_port     = 8000
#     protocol    = "tcp"
#     cidr_blocks = ["10.0.1.0/24"]
#   }

#   ingress {
#     from_port   = 9100
#     to_port     = 9100
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   } 
#   # Egress rules: Define outbound traffic that is allowed. The below configuration allows all outbound traffic from the instance.
#   egress {
#     from_port   = 0                                     # Allow all outbound traffic (from port 0 to any port)
#     to_port     = 0
#     protocol    = "-1"                                  # "-1" means all protocols
#     cidr_blocks = ["0.0.0.0/0"]                         # Allow traffic to any IP address
#   }

#   # Tags for the security group
#   tags = {
#     "Name"      = "sg_ecomm_app2"                          # Name tag for the security group
#     "Terraform" = "true"                                # Custom tag to indicate this SG was created with Terraform
#   }
# }

#######################
# ECOMMERCE APP 1 EC2 #
#######################
resource "aws_instance" "ecommerce_app_az1" {

  ami               = "ami-0866a3c8686eaeeba"                                                
  instance_type     = var.instance_type

  subnet_id = aws_subnet.priv_sub1.id
  vpc_security_group_ids = [aws_security_group.sg_ecomm_app.id] 

  key_name          = "ecommkey"           

  user_data = base64encode(templatefile("${path.module}/deploy.sh", {
        rds_endpoint = aws_db_instance.postgres_db.endpoint,
        docker_user = var.dockerhub_username,
        docker_pass = var.dockerhub_password,
        docker_compose = templatefile("${path.module}/compose.yml", {
        rds_endpoint = aws_db_instance.postgres_db.endpoint
        
        })
        NODE_EXPORTER_VERSION = var.node_exporter_version
    }))

  tags = {
    "Name" = "ecommerce_app_az1"  
    "Terraform" = "true"       
  }

   depends_on = [aws_key_pair.ecommkey]  # Ensure key pair is created first EDIT!!
}

output "ecommerce_app1_privateip" {
  value = aws_instance.ecommerce_app_az1.private_ip # Display the public IP address of the EC2 instance after creation.
}

#######################
# ECOMMERCE APP 2 EC2 #
#######################
resource "aws_instance" "ecommerce_app_az2" {
  
  ami               = "ami-0866a3c8686eaeeba"                                           
  instance_type     = var.instance_type                

  subnet_id = aws_subnet.priv_sub2.id
  vpc_security_group_ids = [aws_security_group.sg_ecomm_app.id]       

  key_name          = "ecommkey"               

  user_data = base64encode(templatefile("${path.module}/deploy.sh", {
        rds_endpoint = aws_db_instance.postgres_db.endpoint,
        docker_user = var.dockerhub_username,
        docker_pass = var.dockerhub_password,
        docker_compose = templatefile("${path.module}/compose.yml", {
        rds_endpoint = aws_db_instance.postgres_db.endpoint
        
        })
        NODE_EXPORTER_VERSION = var.node_exporter_version
    }))

  tags = {
    "Name" = "ecommerce_app_az2"  
    "Terraform" = "true"       
  }
}

output "ecommerce_app2_privateip" {
  value = aws_instance.ecommerce_app_az2.private_ip # Display the public IP address of the EC2 instance after creation.
}

#################
# RDS DATABASE #
#################

resource "aws_db_instance" "postgres_db" {
  identifier           = "ecommerce-db"
  engine               = "postgres"
  engine_version       = "14.13"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "standard"
  db_name              = "W6Database"
  username             = "itsme2"
  password             = "lemondifficult3"
  parameter_group_name = "default.postgres14"
  skip_final_snapshot  = true

  db_subnet_group_name   = aws_db_subnet_group.rds_subgroup.name
  vpc_security_group_ids = [aws_security_group.sg_for_rds.id]

  tags = {
    Name = "Ecommerce Postgres DB"
  }
}

#########################
# SUBNET GROUP FOR RDS # defines the subnets in which the RDS instance will reside.
#########################

resource "aws_db_subnet_group" "rds_subgroup" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.priv_sub1.id, aws_subnet.priv_sub2.id]

  tags = {
    Name = "RDS Subnet Group"
  }
}

#########################
# SECURITY GROUP FOR RDS # controls the inbound and outbound traffic for the RDS instance.
#########################

resource "aws_security_group" "sg_for_rds" {
  name        = "rds_sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.customvpc.id

  ingress {
    from_port       = 5432 #for PostgreSQL
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_ecomm_app.id] 
  }

  # ingress {
  #   from_port   = 9100
  #   to_port     = 9100
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}

output "rds_endpoint" {
  value = aws_db_instance.postgres_db.endpoint
}
