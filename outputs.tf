# output "ssm_nat_instance_id" {
#   value = aws_instance.nat.id
# }

output "a-ssm_nat_command" {
  value = "aws ssm start-session --target ${aws_instance.nat.id} - ${aws_instance.nat.tags["Name"]}"
}

# output "ssm_host_instance_ids" {
#   value = aws_instance.ssm_hosts[*].id
# }

# output "ssm_host_ssm_commands" {
#   value = [
#     for id in aws_instance.ssm_hosts[*].id :
#     "aws ssm start-session --target ${id} - ${aws_instance.nat.tags["Name"]}"
#   ]
# }

output "ssm_host_ssm_commands" {
  value = [
    for i in aws_instance.ssm_hosts :
    "aws ssm start-session --target ${i.id} - ${i.tags["Name"]}"
  ]
}
