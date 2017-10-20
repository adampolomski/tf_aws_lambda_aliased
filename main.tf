variable "s3_bucket" {
  type = "string"
}

variable "s3_key" {
  type = "string"
  default = ""
}

variable "s3_builds_prefix" {
  type = "string"
  default = ""
}

variable "source_code_hash" {
  type = "string"
  default = ""
}

variable "function_variables" {
  type = "map"
  default = {}
}

variable "handler" {
  type = "string"
}

variable "function_name" {
  type = "string"
}

variable "description" {
  type = "string"
  default = ""
}

variable "runtime" {
  type = "string"
  default = "java8"
}

variable "memory_size" {
  type = "string"
  default = 256
}

variable "timeout" {
  type = "string"
  default = 20
}

variable "policy" {
  type = "string"
  default = ""
}

variable "vpc_config" {
  type = "map"
  default = {}
}

variable "dead_letter_target_arn" {
  type = "string"
  default = ""
}

variable "alias" {
  type = "string"
  default = "RELEASE"
}

variable "tags" {
  type = "map"
  default = {}
}

resource "aws_iam_role" "lambda_iam_role" {
  name = "${var.function_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "logs_policy" {
  name = "logs_policy"
  role = "${aws_iam_role.lambda_iam_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "custom_policy" {
  name = "custom_policy"
  role = "${aws_iam_role.lambda_iam_role.id}"
  policy = "${var.policy}"
  count  = "${length(var.policy) > 0 ? 1 : 0}"
}

resource "aws_lambda_function" "lambda_bare" {
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${var.s3_key}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.lambda_iam_role.arn}"
  handler       = "${var.handler}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"
  description   = "${var.description}"
  source_code_hash = "${var.source_code_hash}"
  publish = false

  environment {
    variables = "${var.function_variables}"
  }

  tags = "${var.tags}"

  count = "${length(var.vpc_config) == 0 && length(var.dead_letter_target_arn) == 0 ? 1 : 0}"
}

resource "aws_lambda_function" "lambda_vpc" {
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${var.s3_key}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.lambda_iam_role.arn}"
  handler       = "${var.handler}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"
  description   = "${var.description}"
  source_code_hash = "${var.source_code_hash}"
  publish = false

  vpc_config {
    security_group_ids = [ "${var.vpc_config["security_group_ids"]}" ]
    subnet_ids = [ "${var.vpc_config["subnet_ids"]}" ]
  }

  environment {
    variables = "${var.function_variables}"
  }

  tags = "${var.tags}"

  count = "${length(var.vpc_config) > 0 && length(var.dead_letter_target_arn) == 0 ? 1 : 0}"
}

resource "aws_lambda_function" "lambda_vpc_dead_letter" {
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${var.s3_key}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.lambda_iam_role.arn}"
  handler       = "${var.handler}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"
  description   = "${var.description}"
  source_code_hash = "${var.source_code_hash}"
  publish = false

  vpc_config {
    security_group_ids = [ "${var.vpc_config["security_group_ids"]}" ]
    subnet_ids = [ "${var.vpc_config["subnet_ids"]}" ]
  }

  dead_letter_config {
    target_arn = "${var.dead_letter_target_arn}"
  }

  environment {
    variables = "${var.function_variables}"
  }

  tags = "${var.tags}"

  count = "${length(var.vpc_config) > 0 && length(var.dead_letter_target_arn) > 0 ? 1 : 0}"
}

data "external" "alias" {
  program = ["${path.module}/alias.sh", "${element(concat(aws_lambda_function.lambda_bare.*.function_name, aws_lambda_function.lambda_vpc.*.function_name, aws_lambda_function.lambda_vpc_dead_letter.*.function_name), 0)}"]
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "${var.alias}"
  function_name    = "${element(concat(aws_lambda_function.lambda_bare.*.arn, aws_lambda_function.lambda_vpc.*.arn, aws_lambda_function.lambda_vpc_dead_letter.*.arn), 0)}"
  function_version = "${lookup(data.external.alias.result, var.alias, element(concat(aws_lambda_function.lambda_bare.*.version, aws_lambda_function.lambda_vpc.*.version, aws_lambda_function.lambda_vpc_dead_letter.*.version), 0))}"
}

resource "null_resource" "publisher" {
  triggers {
    alias_id = "${aws_lambda_alias.lambda_alias.id}"
    timeout = "${element(concat(aws_lambda_function.lambda_bare.*.timeout, aws_lambda_function.lambda_vpc.*.timeout, aws_lambda_function.lambda_vpc_dead_letter.*.timeout), 0)}"
    memory_size = "${element(concat(aws_lambda_function.lambda_bare.*.memory_size, aws_lambda_function.lambda_vpc.*.memory_size, aws_lambda_function.lambda_vpc_dead_letter.*.memory_size), 0)}"
    source_code_hash = "${element(concat(aws_lambda_function.lambda_bare.*.source_code_hash, aws_lambda_function.lambda_vpc.*.source_code_hash, aws_lambda_function.lambda_vpc_dead_letter.*.source_code_hash), 0)}"
  }

  provisioner "local-exec" {
    command = "${path.module}/cleanup.sh ${element(concat(aws_lambda_function.lambda_bare.*.function_name, aws_lambda_function.lambda_vpc.*.function_name, aws_lambda_function.lambda_vpc_dead_letter.*.function_name), 0)} ; ${path.module}/publish.sh ${element(concat(aws_lambda_function.lambda_bare.*.function_name, aws_lambda_function.lambda_vpc.*.function_name, aws_lambda_function.lambda_vpc_dead_letter.*.function_name), 0)} ${aws_lambda_alias.lambda_alias.name}"
  }
}

output "lambda_arn" {
  value = "${element(concat(aws_lambda_function.lambda_bare.*.arn, aws_lambda_function.lambda_vpc.*.arn, aws_lambda_function.lambda_vpc_dead_letter.*.arn), 0)}"
}

output "lambda_name" {
  value = "${element(concat(aws_lambda_function.lambda_bare.*.function_name, aws_lambda_function.lambda_vpc.*.function_name, aws_lambda_function.lambda_vpc_dead_letter.*.function_name), 0)}"
}

output "alias_arn" {
  value = "${aws_lambda_alias.lambda_alias.arn}"
}
