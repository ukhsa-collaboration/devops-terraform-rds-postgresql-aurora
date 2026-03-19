moved {
  from = module.cluster.data.aws_iam_policy_document.monitoring_rds_assume_role[0]
  to   = data.aws_iam_policy_document.monitoring_rds_assume_role
}

moved {
  from = module.cluster.data.aws_partition.current
  to   = data.aws_partition.current
}

moved {
  from = module.cluster.data.aws_service_principal.monitoring_rds[0]
  to   = data.aws_service_principal.monitoring_rds
}

moved {
  from = module.cluster.aws_iam_role.rds_enhanced_monitoring[0]
  to   = aws_iam_role.rds_enhanced_monitoring
}

moved {
  from = module.cluster.aws_iam_role_policy_attachment.rds_enhanced_monitoring[0]
  to   = aws_iam_role_policy_attachment.rds_enhanced_monitoring
}

moved {
  from = module.cluster.aws_rds_cluster.this[0]
  to   = aws_rds_cluster.this
}

moved {
  from = module.cluster.aws_rds_cluster_instance.this["instance-1"]
  to   = aws_rds_cluster_instance.this["instance-1"]
}

moved {
  from = module.cluster.aws_rds_cluster_instance.this["instance-2"]
  to   = aws_rds_cluster_instance.this["instance-2"]
}

moved {
  from = module.cluster.aws_rds_cluster_instance.this["instance-3"]
  to   = aws_rds_cluster_instance.this["instance-3"]
}

moved {
  from = module.cluster.aws_rds_cluster_parameter_group.this[0]
  to   = aws_rds_cluster_parameter_group.this
}

moved {
  from = module.cluster.aws_security_group.this[0]
  to   = aws_security_group.this
}

moved {
  from = module.cluster.aws_vpc_security_group_egress_rule.this["self_only"]
  to   = aws_vpc_security_group_egress_rule.this["self_only"]
}

moved {
  from = module.cluster.aws_vpc_security_group_ingress_rule.this["private_subnet_0"]
  to   = aws_vpc_security_group_ingress_rule.this["private_subnet_0"]
}

moved {
  from = module.cluster.aws_vpc_security_group_ingress_rule.this["private_subnet_1"]
  to   = aws_vpc_security_group_ingress_rule.this["private_subnet_1"]
}

moved {
  from = module.cluster.aws_vpc_security_group_ingress_rule.this["private_subnet_2"]
  to   = aws_vpc_security_group_ingress_rule.this["private_subnet_2"]
}
