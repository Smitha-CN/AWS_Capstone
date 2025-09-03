locals {
  name_prefix = "${var.project}-primary"
  tags        = merge({ Project = var.project, Environment = var.environment }, var.tags)
}
