# Project Title

Terraform & Ansible basic WordPress deploy

## Description

Full AWS infrastructure deploy including:
* VPC
* IAM Users
* EC2
* RDS
* ElastiCache

And Ansible deploy WordPress with connection to AWS RDS and Elasticache

## Getting Started

### Dependencies

* Terraform >= v1.9.5
* Ansible >= core 2.16.10

### Installing

* For install just clone the repo
```
git clone https://github.com/denysnemchenko/aws_wordpress.git
```

## Executing program
### Terraform
* Before creating AWS infrastructure you must fill in terraform.tfvars, you can freely change code depending on your purpose
* To create AWS infrastructure, execute this in terraform directory
```
terraform plan -out "your_plan_name"
terraform apply "your_plan_name"
```

After applying Terraform creates vars.yaml with:
* ElastiCache endpoint and port
* RDS endpoint and credentials
* EC2 public domain

Parallel to that, Terraform creates inventory which includes your EC2 public domain and specifying the right private ssh key for it

### Ansible
* Ansible take variables from vars.yaml file that is formed by Terraform
* Before running playbook, you must fill the variable inside vars block in it
* To start deploying just write path to your inventory and playbook
```
ansible-playbook -i ./inventory[formed by Terraform] ./wordpress.yaml
```

After deploy you can easily connect to your EC2 public DNS

## Thats all!