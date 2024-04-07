locals {
  name                   = try(trim(format("%v-bastion", var.prefix_name), 20), "bastion")
  public_ssh_port        = 22
  bastion_instance_count = 1
  disk_size              = 8
  instance_type          = "t3.nano"
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "^amzn2-ami-hvm.*-ebs"

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_iam_policy_document" "assume_policy_document" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion_host_role" {
  count = var.enable ? 1 : 0

  name               = local.name
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_policy_document.json
}

resource "aws_iam_instance_profile" "bastion_host_profile" {
  count = var.enable ? 1 : 0

  role = aws_iam_role.bastion_host_role[0].name
  path = "/"
}

resource "aws_lb" "bastion_lb" {
  count = var.enable ? 1 : 0

  name               = local.name
  subnets            = var.elb_subnets
  load_balancer_type = "network"

  tags = var.tags
}

resource "aws_lb_target_group" "bastion_lb_target_group" {
  count = var.enable ? 1 : 0

  name        = local.name
  port        = local.public_ssh_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    port     = "traffic-port"
    protocol = "TCP"
  }

  tags = var.tags
}

resource "aws_security_group" "bastion_host_security_group" {
  count = var.enable ? 1 : 0

  description = "Enable SSH access to the bastion host from external via SSH port"
  name        = "${local.name}-host"
  vpc_id      = var.vpc_id

  tags = var.tags
}

resource "aws_security_group_rule" "ingress_bastion" {
  count = var.enable ? 1 : 0

  description = "Incoming traffic to bastion"
  type        = "ingress"
  from_port   = local.public_ssh_port
  to_port     = local.public_ssh_port
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group[0].id
}

resource "aws_security_group_rule" "egress_bastion" {
  count = var.enable ? 1 : 0

  description = "Outgoing traffic from bastion to instances"
  type        = "egress"
  from_port   = "0"
  to_port     = "65535"
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.bastion_host_security_group[0].id
}

resource "aws_lb_listener" "bastion_lb_listener_22" {
  count = var.enable ? 1 : 0

  default_action {
    target_group_arn = aws_lb_target_group.bastion_lb_target_group[0].arn
    type             = "forward"
  }

  load_balancer_arn = aws_lb.bastion_lb[0].arn
  port              = local.public_ssh_port
  protocol          = "TCP"
}

resource "aws_launch_template" "bastion_launch_template" {
  count = var.enable ? 1 : 0

  name_prefix            = local.name
  image_id               = data.aws_ami.amazon-linux-2.id
  instance_type          = local.instance_type
  update_default_version = true
  monitoring {
    enabled = false
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = aws_security_group.bastion_host_security_group[*].id
    delete_on_termination       = true
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.bastion_host_profile[0].name
  }
  key_name = var.bastion_ssh_key

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = local.disk_size
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bastion_auto_scaling_group" {
  count = var.enable ? 1 : 0

  name_prefix      = "${local.name}-asg"
  max_size         = local.bastion_instance_count
  min_size         = local.bastion_instance_count
  desired_capacity = local.bastion_instance_count

  launch_template {
    id      = aws_launch_template.bastion_launch_template[0].id
    version = aws_launch_template.bastion_launch_template[0].latest_version
  }

  vpc_zone_identifier = var.auto_scaling_group_subnets

  default_cooldown          = 180
  health_check_grace_period = 180
  health_check_type         = "EC2"

  target_group_arns = [
    aws_lb_target_group.bastion_lb_target_group[0].arn,
  ]

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-asg"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
  }

  lifecycle {
    create_before_destroy = true
  }
}
