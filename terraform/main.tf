#Creating VPC to work with
resource "aws_vpc" "production" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "main"
  }
}

#Creating single IGW
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.production.id
}

#Creating public subnet with IGW
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.production.id
  cidr_block = "172.16.10.0/24"

  depends_on = [aws_internet_gateway.gw]

  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public"
  }
}

#Creating 2 private subnet with availability zone to satisfy RDS requirements
resource "aws_subnet" "private-1" {
  vpc_id     = aws_vpc.production.id
  cidr_block = "172.16.20.0/24"

  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-1"
  }
}
resource "aws_subnet" "private-2" {
  vpc_id     = aws_vpc.production.id
  cidr_block = "172.16.30.0/24"

  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-2"
  }
}

#Declaring route tables for public subnet with IGW, for two private subnets we dont need IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.production.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

#Associating route tables with subnets
resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = aws_subnet.public.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.production.id
}

resource "aws_route_table_association" "private-1" {
  route_table_id = aws_route_table.private_rt.id
  subnet_id      = aws_subnet.private-1.id
}
resource "aws_route_table_association" "private-2" {
  route_table_id = aws_route_table.private_rt.id
  subnet_id      = aws_subnet.private-2.id
}
# Creating security group for EC2 instance
resource "aws_security_group" "wordpress_sg" {
  name        = "wordpress_sg"
  description = "default"
  vpc_id      = aws_vpc.production.id

  #Allow only 80 port(HTTP) for wordpress connection
  ingress {
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  #Allow port 22 for SSH, but only for our single public ip(your office or home or vpn)
  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["${var.home}/32"]
  }
  #Egress any traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress_sg"
  }

}

#Creating security group for database
resource "aws_security_group" "rds_sg" {
  name   = "mysql_sg"
  vpc_id = aws_vpc.production.id
  #Allow only default mysql port, and allow connection only for EC2 private ip
  ingress {
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  tags = {
    Name = "rds_db"
  }

}
#Cache security group
resource "aws_security_group" "cache_sg" {
  name   = "elasticache_sg"
  vpc_id = aws_vpc.production.id
  #Allow default redis port and connection only from EC2 private ip
  ingress {
    from_port       = "6379"
    to_port         = "6379"
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }

  tags = {
    Name = "cache_sg"
  }

}
#Creating database subnet, including two subnets for requirements of high availability
resource "aws_db_subnet_group" "rds_subnet" {
  name       = "rds_subnet"
  subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id]
}

#RDS instance with 10g of allocated storage with mysql engine
resource "aws_db_instance" "default" {
  instance_class      = "db.t3.micro"
  allocated_storage   = 10
  db_name             = var.db_name
  engine              = "mysql"
  engine_version      = "8.0"
  username            = var.db_user
  password            = var.db_pass
  skip_final_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

}

#Adding your pubkey into AWS
resource "aws_key_pair" "keys" {
  key_name   = "client"
  public_key = file(var.pub_key)
}

#ElastiCache subnet group, two subnets with availability zones(Again, because of requirements )
resource "aws_elasticache_subnet_group" "cache_group" {
  name       = "cachesub"
  subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id]
}

#ElastiCache cluster with 1 node with redis engine
resource "aws_elasticache_cluster" "redis" {
  cluster_id         = "rediscluster"
  engine             = "redis"
  node_type          = "cache.t3.micro"
  num_cache_nodes    = 1
  engine_version     = "7.1"
  port               = 6379
  subnet_group_name  = aws_elasticache_subnet_group.cache_group.name
  security_group_ids = [aws_security_group.cache_sg.id]
}

#Main EC2 instance for wordpress, using Ubuntu 24.04 LTS AMI, connecting only one security group which have access to db and cache SG's
resource "aws_instance" "wordpress" {
  ami           = "ami-09a9858973b288bdd"
  subnet_id     = aws_subnet.public.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.keys.key_name

  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]

  tags = {
    Name = "wordpress"
  }
}

#Our public ip for EC2
resource "aws_eip" "wordpress_eip" {
  instance = aws_instance.wordpress.id
  tags = {
    Name = "wordpress_eip"
  }
}

#Creating IAM Users
resource "aws_iam_user" "wordpress" {
  name = "Wordpress"
}

resource "aws_iam_user" "aws_client" {
  name = "aws_client"
}

#Creating access keys for them
resource "aws_iam_access_key" "wordpress_access_key" {
  user = aws_iam_user.wordpress.name
}

resource "aws_iam_access_key" "aws_client_access_key" {
  user = aws_iam_user.aws_client.name
}

#Giving the client ViewOnlyAccess AWS Managed policy
resource "aws_iam_user_policy_attachment" "aws_client" {
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
  user       = aws_iam_user.aws_client.name
}

#Giving the client permission to log in into AWS Console
resource "aws_iam_user_login_profile" "client_console" {
  user            = aws_iam_user.aws_client.name
  password_length = 20
}

#Creating ReadOnly policy on EC2 for Wordpress user
resource "aws_iam_policy" "ReadOnly" {
  name        = "ReadOnly"
  path        = "/"
  description = "ReadOnly"
  policy      = file("ReadOnly.json")
}

#Applying policies to users
resource "aws_iam_user_policy_attachment" "wordpress" {
  policy_arn = aws_iam_policy.ReadOnly.arn
  user       = aws_iam_user.wordpress.name
}

output "wordpress-IP" {
  value = aws_eip.wordpress_eip.public_ip
}

output "wordpress-dns" {
  value = aws_eip.wordpress_eip.public_dns
}

output "database-endpoint" {
  value = aws_db_instance.default.address
}

output "cache-endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes.0.address
}

#Wait 15s, sometime public domain are created after localfile provisioner
resource "time_sleep" "sleep_15" {
  create_duration = "15s"
}

#Forming variables for ansible playbook
resource "local_file" "vars" {
  filename   = "../playbook/vars.yaml"
  depends_on = [time_sleep.sleep_15]
  content    = "cache_endpoint: \"${aws_elasticache_cluster.redis.cache_nodes.0.address}\"\ncache_port: \"${aws_elasticache_cluster.redis.port}\"\nwordpress_domain: \"${aws_instance.wordpress.public_dns}\"\nwordpress_db_endpoint: \"${aws_db_instance.default.endpoint}\"\nwordpress_db: \"${aws_db_instance.default.db_name}\"\nwordpress_db_user: \"${aws_db_instance.default.username}\"\nwordpress_db_pass: \"${aws_db_instance.default.password}\"\n"
}

#Forming inventory for ansible including ssh private key(Declared in variables and terraform.tfvars)
resource "local_file" "ansible_inventory" {
  filename = "../playbook/inventory"
  content  = "[wordpress]\n${aws_eip.wordpress_eip.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${var.priv_key}"
}

#Output for credentials
resource "local_file" "credentials" {
  filename = "credentials"
  content  = "User:${aws_iam_user.aws_client.name}\nToken:${aws_iam_access_key.aws_client_access_key.secret}\nPass:${aws_iam_user_login_profile.client_console.password}\nUser:${aws_iam_user.wordpress.name}\nToken:${aws_iam_access_key.wordpress_access_key.secret}"
}