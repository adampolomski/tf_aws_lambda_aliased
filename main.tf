variable "s3_bucket" {
  type = "string"
}

variable "s3_key" {
  type = "string"
}

variable "environment" {
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
}

data "external" "aliases" {
  program = ["${path.module}/aliases.sh", "${aws_lambda_function.lambda.function_name}"]
}

resource "aws_iam_role" "lambda_iam_role" {
  name = "${var.function_name}_iam_role"

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
}

resource "aws_lambda_function" "lambda" {
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${var.s3_key}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.lambda_iam_role.arn}"
  handler       = "${var.handler}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"
  description   = "${var.description}"
  environment {
    variables = "${var.environment}"
  }
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "${element(keys(data.external.aliases.result), count.index)}"
  function_name    = "${aws_lambda_function.lambda.arn}"
  function_version = "${lookup(data.external.aliases.result, element(keys(data.external.aliases.result), count.index))}"

  #count = "${length(keys(data.external.aliases.result))}" This won't work yet. Hardcoding count to 2.
  count = 2
}

output "lambda_arn" {
  value = "${aws_lambda_function.lambda.arn}"
}

output "alias_production_arn" {
  value = "${aws_lambda_alias.lambda_alias.0.arn}"
}

output "alias_test_arn" {
  value = "${aws_lambda_alias.lambda_alias.1.arn}"
}
