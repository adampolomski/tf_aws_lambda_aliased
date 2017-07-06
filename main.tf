variable "s3_bucket" {
  type = "string"
}

variable "s3_builds_prefix" {
  type = "string"
}

variable "build_path" {
  type = "string"
}

variable "function_variables" {
  type = "map"
  default = {foo = "bar"}
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

variable "aliases" {
  type = "map"
  default = {
    prod = "PRODUCTION"
    test = "TEST"
  }
}

resource "aws_iam_role" "lambda_iam_role" {
  name = "${var.function_name}_${terraform.env}_iam_role"

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

resource "aws_s3_bucket_object" "object" {
  bucket = "${var.s3_bucket}"
  key    = "${var.s3_builds_prefix}${basename(var.build_path)}"
  source = "${var.build_path}"
  etag   = "${md5(file(var.build_path))}"
}

resource "aws_lambda_function" "lambda" {
  s3_bucket     = "${aws_s3_bucket_object.object.bucket}"
  s3_key        = "${aws_s3_bucket_object.object.key}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.lambda_iam_role.arn}"
  handler       = "${var.handler}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"
  description   = "${var.description}"
  publish = false
  environment {
    variables = "${var.function_variables}"
  }
  source_code_hash = "${base64sha256(file(var.build_path))}"
}

data "external" "alias" {
  program = ["${path.module}/alias.sh", "${aws_lambda_function.lambda.function_name}"]
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "${lookup(var.aliases, terraform.env, upper(terraform.env))}"
  function_name    = "${aws_lambda_function.lambda.arn}"
  function_version = "${lookup(data.external.alias.result, lookup(var.aliases, terraform.env, upper(terraform.env)), aws_lambda_function.lambda.version)}"
}

resource "null_resource" "publisher" {
  triggers {
    timeout = "${aws_lambda_function.lambda.timeout}"
    memory_size = "${aws_lambda_function.lambda.memory_size}"
    code_hash = "${aws_lambda_function.lambda.source_code_hash}"
  }

  provisioner "local-exec" {
    command = "${path.module}/publish.sh ${aws_lambda_function.lambda.function_name} ${aws_lambda_alias.lambda_alias.name}"
  }
}

output "lambda_arn" {
  value = "${aws_lambda_function.lambda.arn}"
}

output "alias_arn" {
  value = "${aws_lambda_alias.lambda_alias.arn}"
}
