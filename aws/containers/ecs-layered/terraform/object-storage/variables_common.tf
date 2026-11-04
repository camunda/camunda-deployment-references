variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource created by this root"
}
