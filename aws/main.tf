provider "aws" {
  region  = "us-east-1"
}

resource "aws_ecr_repository" "my_ecr_repo" {
  name = "gorilla-ecr-repo"
}

resource "aws_ecs_cluster" "my_ecs_cluster" {
  name = "gorilla-ecs-cluster"
}

resource "aws_ecs_task_definition" "my_ecs_task" {
  family                   = "gorilla-ecs-task"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "gorilla-ecs-task",
      "image": "${aws_ecr_repository.my_ecr_repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000,
          "protocol": "tcp"
        }
      ],
      "memory": 512,
      "cpu": 256,
      "environment": [],
      "mountPoints": [],
      "volumesFrom": []
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_vpc" "main" {
  cidr_block = "10.20.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
}

resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = "true"
  cidr_block = "10.20.1.0/24"
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.main.id  
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = "true"
  cidr_block = "10.20.2.0/24"
}

resource "aws_subnet" "subnet_c" {
  vpc_id            = aws_vpc.main.id
  availability_zone = "us-east-1c"
  map_public_ip_on_launch = "true"
  cidr_block = "10.20.3.0/24"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_security_group" "load_balancer_security_group" {
  vpc_id      = aws_vpc.main.id  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_alb" "application_load_balancer" {
  name               = "gorilla-lb-tf"
  internal           = false
  load_balancer_type = "application"
  subnets = [
    "${aws_subnet.subnet_a.id}",
    "${aws_subnet.subnet_b.id}",
    "${aws_subnet.subnet_c.id}"
  ]
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_vpc.main.id}"
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
  depends_on = [
    aws_alb.application_load_balancer
  ]
}

resource "aws_security_group" "service_security_group" {
  vpc_id      = aws_vpc.main.id  
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "my_ecs_service" {
  name            = "gorilla-ecs-service"
  cluster         = "${aws_ecs_cluster.my_ecs_cluster.id}"
  task_definition = "${aws_ecs_task_definition.my_ecs_task.arn}"
  launch_type     = "FARGATE"
  desired_count   = 3

  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
    container_name   = "${aws_ecs_task_definition.my_ecs_task.family}"
    container_port   = 3000
  }

  network_configuration {
    subnets          = ["${aws_subnet.subnet_a.id}", "${aws_subnet.subnet_b.id}", "${aws_subnet.subnet_c.id}"]
    assign_public_ip = true
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Setting the security group

  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}"
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
  }
}

output "alb_hostname" {                                                         
   value = aws_alb.application_load_balancer.dns_name                                                 
} 