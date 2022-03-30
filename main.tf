# Terraform configuration

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.21.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.vpc_azs
  private_subnets = var.vpc_private_subnets
  public_subnets  = var.vpc_public_subnets

  enable_nat_gateway = var.vpc_enable_nat_gateway

  tags = var.vpc_tags
}

module "vote_service_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "user-service"
  description = "Security group for user-service with custom ports open within VPC, and PostgreSQL publicly open"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks      = ["10.10.0.0/16"]
  ingress_rules            = ["https-443-tcp"]
  ingress_with_cidr_blocks = [
    {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = "0.0.0.0/0"


    },
     {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = "0.0.0.0/0"


    },

    {
      rule        = "postgresql-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}







module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name   = "deployer-two"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC6W6grQHcSdmR2ddQ1pXh4xtYeH38iKASRIpG91wW6Zju14/YsJH2BvKAyV+ptTNcud4hbHQQuefgMT3sXtgH+ERXGWrzk1hYf5l6buKA7qutOmN24+XSW85fvTUEtbdxMNzGhomqMxIeBaEqqwHl94Oh5G1KZndcTpRz58dpe9H4oUqou4XiAn3dNvOh2zd/HJS6L8RTXk6qesRyf1/dP+VRut345eb5Dx0TVLOjDwJpUJJ6wVj5Vls3ENzFXZxL/aF3QnDCScNE8jfCTOMu529lMzEVOnfAH2RtZ8DQ+I1BLgl5wod3QdKX4yir9mv76zs7RVvT30RpSJGKkFiKspCAOtlFm5gu9bm4VATjJEzLc75zN6DHwESD8zOU3eFS03p8IEjtauCcgo7Sy0PQWMnlytqG+PSJpKnVecJJiYKy3MvBZ+g+khi2s0jOigdAf2UjRFyuNmSt202huNZmGE2UglOEOvcndn5Gl5GFULIz9LquK+6ZN/o8bSi/7E90= yassine@yassine-VirtualBox"
}



module "ec2_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "2.12.0"

  name           = "my-ec2-cluster"
  instance_count = 2

  ami                    = "ami-04505e74c0741db8d"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [module.vote_service_sg.security_group_id]
  subnet_id              = module.vpc.public_subnets[0]
  key_name               = module.key_pair.key_pair_key_name



  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
 
  
}
resource "local_file" "hosts_cfg" {
  content = templatefile("templates/hosts.tfpl",
    {
      web_machines =tolist(module.ec2_instances.public_ip)
    }
  )
  filename = "ansible/inventory/hosts.cfg"
}

resource "local_file" "foo" {
   source = "ansible/inventory/hosts.cfg"
   filename = "ansible/inventory/hosts.cfg"
}

resource "null_resource" "cluster" {

 triggers = {
    file_changed = md5(local_file.foo.source)
  }

  # Changes to any instance of the cluster requires re-provisioning
 # triggers = {
  #  cluster_instance_ids = "${join(",", tolist(module.ec2_instances.*.id) )}"
 # }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
 # connection {
  #  host = "${element( tolist(module.ec2_instances.public_ip) , 0)}"
 # }

 provisioner "local-exec" {
    command = "export ANSIBLE_HOST_KEY_CHECKING=False"
  }
  provisioner "local-exec" {
  
  command = "ansible-playbook ansible/playbook.yaml -i ansible/inventory/hosts.cfg -u ubuntu --private-key ../learn-terraform-modules-use/ssh_key/ec2_key"
    
    
  }
  
}




