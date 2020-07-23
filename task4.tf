provider "aws" {
  region   = "ap-south-1"
  profile  = "default"
}

////VPC
resource "aws_vpc" "task-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames  = true

  tags = {
    Name = "task-vpc"
  }
}


////Public Subnet
resource "aws_subnet" "public-subnet" {
	depends_on = [aws_vpc.task-vpc]

  vpc_id     = aws_vpc.task-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "public-subnet"
  }
}


////Private Subnet
resource "aws_subnet" "private-subnet" {
	depends_on = [aws_vpc.task-vpc]

  vpc_id     = aws_vpc.task-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "private-subnet"
  }
}


/////Elastic IP
resource "aws_eip" "task-eip" {

  vpc      = true
  
}


/////NAT Gateway
resource "aws_nat_gateway" "task-ntg" {
  allocation_id = aws_eip.task-eip.id
  subnet_id     = aws_subnet.public-subnet.id
}


////Internet Gateway
resource "aws_internet_gateway" "internet-gateway" {
	depends_on = [aws_vpc.task-vpc]

  vpc_id = aws_vpc.task-vpc.id

  tags = {
    Name = "internet-gateway"
  }
}


////Route Table for Internet Gateway
resource "aws_route_table" "route-table-ig" {
  vpc_id = aws_vpc.task-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }

  tags = {
    Name = "route-table-ig"
  }
}
resource "aws_route_table_association" "association-with-public-subnet" {
	depends_on = [aws_route_table.route-table-ig]

  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.route-table-ig.id
}



////Route Table for NAT Gateway
resource "aws_route_table" "route-table-nat" {
  vpc_id = aws_vpc.task-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }

  tags = {
    Name = "route-table-nat"
  }
}
resource "aws_route_table_association" "association-with-private-subnet" {
	depends_on = [aws_route_table.route-table-nat]

  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.route-table-nat.id
}



////Security Group for WordPress
resource "aws_security_group" "wordpress" {
	depends_on = [aws_vpc.task-vpc]

  name        = "wordpress"
  vpc_id      = aws_vpc.task-vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "SSH"
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

  tags = {
    Name = "sg-wordpress"
  }
}


////Security Group for MySQL
resource "aws_security_group" "mysql" {
	depends_on = [aws_vpc.task-vpc]

  name        = "mysql"
  vpc_id      = aws_vpc.task-vpc.id

  ingress {
    description = "MYSQL"
    security_groups = [aws_security_group.wordpress.id]
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    
  }
  ingress {
    description = "SSH"
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

  tags = {
    Name = "mysql"
  }
}



//////Key Pair
resource "tls_private_key" "ssh_key_gen" {
  algorithm   = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "task4" {
  depends_on = [
		tls_private_key.ssh_key_gen
]
  key_name   = "task4"
  public_key = tls_private_key.ssh_key_gen.public_key_openssh
}

resource "local_file" "private_file1" {
  depends_on = [
     aws_key_pair.task4
  ]

  content  = tls_private_key.ssh_key_gen.private_key_pem
  filename = "task4.pem"

}


////WordPress Instance
resource "aws_instance" "wordpress-instance" {
  ami                    = "ami-7e257211"
  availability_zone      = "ap-south-1a"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public-subnet.id
  vpc_security_group_ids = [ aws_security_group.wordpress.id ]
  associate_public_ip_address = true
  key_name = "task4"
  
  tags = {
    Name = "wordpress-instance"
    }
	
}


/////MySQL Instance
resource "aws_instance" "mysql-instance" {
  ami                    = "ami-0447a12f28fddb066"
  availability_zone      = "ap-south-1b"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private-subnet.id
  vpc_security_group_ids = [ aws_security_group.mysql.id ]
  associate_public_ip_address = true
  key_name = "task4"
  
  tags = {
    Name = "mysql-instance"
    }
}



/////Bastion Host
resource "aws_security_group" "bastion-host-sg" {
	depends_on = [aws_vpc.task-vpc]

  name        = "bastion-host-sg"
  vpc_id      = aws_vpc.task-vpc.id

  ingress {
    description = "SSH"
    security_groups = [aws_security_group.wordpress.id]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion-host-sg"
  }
}

resource "aws_instance" "bastion-host" {
  ami           = "ami-0732b62d310b80e97"
  availability_zone = "ap-south-1a"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public-subnet.id
  vpc_security_group_ids = [ aws_security_group.bastion-host-sg.id ]
  associate_public_ip_address = true
  key_name = "task4"
  
  tags = {
    Name = "bastion-host"
    }
}
