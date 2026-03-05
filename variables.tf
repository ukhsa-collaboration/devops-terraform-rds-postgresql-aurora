variable "engine_version" {
  description = "Version of the RDS engine"
  type        = string

  validation {
    condition     = can(regex("^\\d+", var.engine_version))
    error_message = "engine_version must start with a major version number, e.g. 14.11 or 15.4."
  }
}

variable "project_short_name" {
  description = "Short project identifier used in resource naming prefix (e.g. c25k)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_short_name))
    error_message = "project_short_name must contain only lowercase letters and numbers."
  }
}

variable "environment_name" {
  description = "The name of the environment"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment_name))
    error_message = "environment_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment_tier" {
  description = "Environment policy tier that controls opinionated defaults."
  type        = string
  default     = "Development"

  validation {
    condition     = contains(["Production", "PreProduction", "Development"], var.environment_tier)
    error_message = "environment_tier must be one of: Production, PreProduction, Development."
  }
}

variable "backup_retention_period" {
  description = "Optional override for backup retention days. If null, environment_tier defaults are used."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 1 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be null or between 1 and 35."
  }

  validation {
    condition     = var.environment_tier != "Production" || var.backup_retention_period == null || var.backup_retention_period >= 14
    error_message = "For Production, backup_retention_period override must be null or at least 14 days."
  }
}

variable "deletion_protection" {
  description = "Flag to protect the RDS instance from accidental deletion."
  type        = bool
  default     = true

  validation {
    condition     = var.environment_tier != "Production" || var.deletion_protection
    error_message = "deletion_protection must be true when environment_tier is Production."
  }
}

variable "master_username" {
  description = "Master username for Aurora cluster."
  type        = string
  default     = "root"
}

variable "preferred_backup_window" {
  description = "Optional override for backup window (UTC), e.g. 03:00-04:00."
  type        = string
  default     = null

  validation {
    condition     = var.preferred_backup_window == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.preferred_backup_window))
    error_message = "preferred_backup_window must be null or match HH:MM-HH:MM (UTC)."
  }
}

variable "preferred_maintenance_window" {
  description = "Optional override for maintenance window (UTC), e.g. sun:04:00-sun:05:00."
  type        = string
  default     = null

  validation {
    condition     = var.preferred_maintenance_window == null || can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must be null or match ddd:HH:MM-ddd:HH:MM (UTC)."
  }
}

variable "db_subnet_group_name" {
  description = "Optional existing DB subnet group name. If null, defaults to the VPC name pattern (<name_prefix>-vpc-main)."
  type        = string
  default     = null
}

variable "min_capacity" {
  description = "The minimum number of Aurora capacity units (ACUs) for a DB instance in an Aurora Serverless v2 cluster."
  type        = number

  validation {
    condition     = var.min_capacity >= 0 && var.min_capacity <= 128 && floor(var.min_capacity * 2) == var.min_capacity * 2
    error_message = "min_capacity must be between 0 and 128 in 0.5 increments."
  }
}

variable "max_capacity" {
  description = "The maximum number of Aurora capacity units (ACUs) for a DB instance in an Aurora Serverless v2 cluster."
  type        = number

  validation {
    condition     = var.max_capacity >= 0.5 && var.max_capacity <= 128 && floor(var.max_capacity * 2) == var.max_capacity * 2 && var.max_capacity >= var.min_capacity
    error_message = "max_capacity must be between 0.5 and 128 in 0.5 increments and be >= min_capacity."
  }
}

variable "instance_count" {
  description = "Number of Aurora cluster instances to create."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15
    error_message = "instance_count must be between 1 and 15."
  }
}

variable "enable_http_endpoint" {
  description = "Enable Aurora Data API (disabled by default for tighter security posture)"
  type        = bool
  default     = false
}

variable "enable_control_tower_backup_hourly" {
  description = "Enable Control Tower hourly backup tag on the cluster."
  type        = bool
  default     = false
}

variable "enable_control_tower_backup_daily" {
  description = "Enable Control Tower daily backup tag on the cluster."
  type        = bool
  default     = false
}

variable "enable_control_tower_backup_weekly" {
  description = "Enable Control Tower weekly backup tag on the cluster."
  type        = bool
  default     = false
}

variable "enable_control_tower_backup_monthly" {
  description = "Enable Control Tower monthly backup tag on the cluster."
  type        = bool
  default     = false
}
