# --- 1. PROVIDER CONFIGURATION ---
provider "aws" {
  region = "us-east-1"
}

# --- 2. DATA SOURCES ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = ["us-east-1a"] 
  }
}

# --- 3. KEY PAIR RESOURCE ---
resource "aws_key_pair" "emr_key" {
  key_name   = "${var.netid}-emergency-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCxl4kaiyzWsERj5L4fS7UbmRxlRLym91VKDIS1U2cLnIOjiwr48cnyJwF1TSKx87Rd6ekPz2jGlndLDo6CSnf5YQgkLr5TQnnPBk1A9OSy5U2lPFUr83teallYVgxSv6z7uBRFkwYRdSwoVfNNv7XbLQI2mdSNHCzwuessk+JEgwXIl/aN3IYq+dPnXYYbI/K2sjPm61xTT9sMltHBohyQPVaAJtiNYUi51t/YpwsJJUw5WhnQb/I9oCGb1qZxxbc9jgKdrjOCsYfRZmc0xfxSG64QXHLUG2aQyspOwpWyuylUhBatFXML4wsA7j7yINJGBAO1r0xt+r28/zCw+7fPAXhK/dqpe5paWF/Ojf6q/v0hFf0UB3QvZTIXXBvOPTXIdez7t1SqKKPnuRVDinX1V1BVn4vBVS/Sc+yUOGUC6OebJh7CmdQ7NkdAsbgmRJw3NRwjkSNIHs4UubYa78GBFVzxMHTdQeDiDRt/xSiiIvwwI1eKO5uEmyKXrPiJZEwJsgQhAi5IreOFqJpq2L0UYgV1wuFsPBF/9ryA4MGr4SWTBXnUdBVKlgR8+5TDgzktP019dhdZnBAzQr7mxZV7evh5FvURC9SqR16d3duLtERjcRbO23me51G4VcZDUj+p+KpGpWsPbg61NXGOKCrZYFKVbnIWZZwOZbhbnUjM/w== pc@LAPTOP-1MMVMUT9"
}

# --- 4. SECURITY GROUP ---
resource "aws_security_group" "deploy_sg" {
  name        = "${var.netid}-emergency-deploy-sg"
  description = "Security group for model serving on Default VPC"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ollama API Access"
    from_port   = 11434
    to_port     = 11434
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

# --- 5. IAM ROLE FOR S3 ACCESS ---
resource "aws_iam_role" "deploy_s3_role" {
  name = "${var.netid}-emergency-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attach" {
  role       = aws_iam_role.deploy_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "deploy_profile" {
  name = "${var.netid}-emergency-instance-profile"
  role = aws_iam_role.deploy_s3_role.name
}

# --- 6. EC2 INSTANCE ---
resource "aws_instance" "model_server" {
  ami           = "ami-091138d0f0d41ff90" 
  instance_type = "t2.xlarge"          

  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.deploy_sg.id]
  associate_public_ip_address = true
  
  iam_instance_profile        = aws_iam_instance_profile.deploy_profile.name
  key_name                    = aws_key_pair.emr_key.key_name

  root_block_device {
    volume_size = 133 
    volume_type = "gp3"
  }


  user_data = <<-EOF
              #!/bin/bash
              curl -fsSL https://ollama.com/install.sh | sh
              EOF

  tags = {
    Name = "${var.netid}-Emergency-Model-Node"
  }
}

# --- 7. OUTPUTS ---
output "deploy_node_public_ip" {
  value = aws_instance.model_server.public_ip
}