# --- 1. SSH KEY PAIR ---
# This creates the key in AWS. 
# Replace the 'public_key' string with your actual ssh-rsa public key.
resource "aws_key_pair" "emr_key" {
  key_name   = "${var.netid}-emr-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDJnp9wf5cdEAob5T+X6+ayadQvWMOAcG8lHgaT8f++e1SkEzQ1FaoRAAahcnQtCz8qLAc9b7G63tEvXZxacQ70plZLCHyUFg7PunNBmrbCDOwhjAlJ3ZE5q7nnYcI2IR28uS+QCV62cZSR+PjAr/mJ9iD+8HZidWFU1rzjNhI06LrkPv+QF+Cb18hE138TmabIy3edbywuFSAPdKfGhto66jCQHIaXfGp1M6O87RXx2KEs7QsoAI6EP7xOrZS0Ozh5liVYU7W85VCYCtS622YNm9A4dfWzHWDhGscaFofLvEBcXgo+0IG0fmwjU9OgaLmsJNYPhOgP6gFNR9NpYN4HugYifrv15SvNbnrSTiICIBc0+hLqoLT9tiOnzBrk3Sn7rM25jBhNZgGV71FKGoDvLOD6s0BB0gVs/5Fv6dasrbQ8ieU4ZjHfal2aLqAGVu5/pPod6UtAkkIIjnFcxClZx51eBCPm8UWvxAIpJfgVaMEQBjBZpEP7ps19zPUpJeBq32qTHWpiRSaYUJZIwKlbyWhG2O1vPPF6/ZFWIrTyzz2n9ewQUULiOFQ8dbjFJkOz3a0K7ZH7PqBxCMAZyUDozrXNDkhbIy3+IeTQpcHgiybkPDzcpeAXgfZqlvxMcoRxtlGrMsGwFsIwdPD68DQKZAmCVk7o5T5QnmjiiOL9OQ== braveboy911@TheMaster"
}

provider "aws" {
  region = "us-east-1"
}

# --- 2. VPC & NETWORKING ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "${var.netid}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.netid}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.netid}-public-subnet" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.netid}-public-rt" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.rt.id
}

# --- 3. SECURITY GROUP ---
resource "aws_security_group" "common_sg" {
  name        = "${var.netid}-common-sg"
  description = "Allow SSH and Internal Traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.netid}-sg" }
}

# --- 4. S3 BUCKET ---
resource "aws_s3_bucket" "project_storage" {
  bucket        = "${var.netid}-cisc886-project-data"
  force_destroy = true
  tags          = { Name = "${var.netid}-s3-bucket" }
}

# --- 5. EMR CLUSTER ---
resource "aws_emr_cluster" "cluster" {
  name          = "${var.netid}-tech-support-cluster"
  release_label = "emr-7.13.0"
  applications  = ["Spark", "Hadoop", "JupyterEnterpriseGateway"]

  service_role           = "EMR_DefaultRole"
  termination_protection = false

  ec2_attributes {
    subnet_id                         = aws_subnet.public.id
    emr_managed_master_security_group = aws_security_group.common_sg.id
    emr_managed_slave_security_group  = aws_security_group.common_sg.id
    instance_profile                  = "EMR_EC2_DefaultRole"

    # ✅ SSH KEY ADDED HERE
    key_name = aws_key_pair.emr_key.key_name
  }

  master_instance_group {
    instance_type = "r8g.xlarge"
    name          = "Master - ${var.netid}"
  }

  core_instance_group {
    instance_type  = "r8g.xlarge"
    instance_count = 1
    name           = "Core - ${var.netid}"

    ebs_config {
      size                 = 50
      type                 = "gp3"
      volumes_per_instance = 1
    }
  }

  tags = { Name = "${var.netid}-emr-cluster" }
}

# --- 6. OUTPUTS ---
output "s3_bucket_name" {
  value = aws_s3_bucket.project_storage.bucket
}

output "emr_cluster_id" {
  value = aws_emr_cluster.cluster.id
}
