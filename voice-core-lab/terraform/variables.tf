variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "project" {
  description = "Short name used to prefix resources (keep it under 14 characters)."
  type        = string
  default     = "voicecore"
}

variable "instance_type" {
  description = "EC2 instance type for the SIP nodes."
  type        = string
  default     = "t3.micro"
}

variable "allowed_cidr" {
  description = "Your public IP in CIDR form, for example 203.0.113.10/32. Only this range can reach SIP port 5060."
  type        = string
}

variable "repo_url" {
  description = "HTTPS URL of your PUBLIC GitHub repo that contains this project, for example https://github.com/you/voice-core-lab.git"
  type        = string
}
