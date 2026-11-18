# Parent module: composes the three children. Resource names/behavior are unchanged
# from the earlier flat layout; the moved blocks in moved.tf migrate existing state.

module "log_group" {
  source = "./modules/log_group"
  name   = var.name
}

module "exec_role" {
  source        = "./modules/exec_role"
  name          = var.name
  log_group_arn = module.log_group.arn
}

module "function_url" {
  source               = "./modules/function_url"
  name                 = var.name
  role_arn             = module.exec_role.arn
  zip_path             = var.zip_path
  reserved_concurrency = var.reserved_concurrency

  # Log group and logging policy must exist before the function can first log.
  depends_on = [module.log_group, module.exec_role]
}
