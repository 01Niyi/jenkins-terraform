# configured aws provider with proper credentials
provider "aws" {
  region  = "us-east-1"
}

# create default vpc if one does not exit
resource "aws_default_vpc" "default_vpc" {

  tags = {
    Name = "default vpc"
  }
}


# use data source to get all avalablility zones in region
data "aws_availability_zones" "available_zones" {}


# create default subnet if one does not exit
resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available_zones.names[0]

  tags = {
    Name = "default subnet"
  }
}


# create security group for the ec2 instance
# ingress cidr_blocks is my IP address
# port 8080 is what jenkins works on
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2 security group"
  description = "allow access on ports 80 and 22"
  vpc_id      = aws_default_vpc.default_vpc.id

  ingress {
    description = "http proxy access"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["73.163.162.63/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2 security group"
  }
}


# use data source to get a registered amazon linux 2 ami
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}


# launch the ec2 instance and install website
resource "aws_instance" "jenkins-server" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_default_subnet.default_az1.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  key_name               = "ec2_key"
# user_data              = file("install-jenkins.sh")
# using 'file function' as seen above in line 90

  tags = {
    Name = "jenkins-server"
  }
}

# an empty resource block
resource "null_resource" "name" {

  # ssh into the ec2 instance 
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("~/Downloads/ec2_key.pem")
    host        = aws_instance.jenkins-server.public_ip
  }

  # copy the install-jenkins.sh file from your computer to the ec2 instance 
  provisioner "file" {
    source      = "install-jenkins.sh"
    destination = "/tmp/install-jenkins.sh"
  }

  # set permissions and run the install-jenkins.sh file
  provisioner "remote-exec" {
    inline = [
        "sudo chmod +x /tmp/install-jenkins.sh",
        "sh /tmp/install-jenkins.sh",
    ]
  }

  # wait for ec2 to be created
  depends_on = [aws_instance.jenkins-server]
}

# print the url of the jenkins server
output "website_url" {
  value = join("", ["http://", aws_instance.jenkins-server.public_dns, ":", "8080"])
}
