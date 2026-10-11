output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "security_group_ids" {
  value = {
    alb       = module.network.alb_sg_id
    ecs       = module.network.ecs_sg_id
    rds       = module.network.rds_sg_id
    ec2_admin = module.network.ec2_admin_sg_id
  }
}
