output "nlb_dns_name" {
  description = "Point SIP clients and the SIPp tests at this name, port 5060."
  value       = aws_lb.sip.dns_name
}

output "instance_ids" {
  description = "The two Kamailio nodes, one per availability zone."
  value       = aws_instance.kamailio[*].id
}

output "availability_zones" {
  description = "Availability zones in use."
  value       = local.azs
}
