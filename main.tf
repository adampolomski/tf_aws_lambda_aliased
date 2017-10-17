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
  default = ""
}

variable "vpc_config" {
  type = "map"
  default = {
    security_group_ids = []
    subnet_ids = []
  }
}

variable "alias" {
  type = "string"
  default = "RELEASE"
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

resource "aws_s3_bucket_object" "object" {
  bucket = "${var.s3_bucket}"
  key    = "${var.s3_builds_prefix}${basename(var.build_path)}"
  source = "${var.build_path}"
  etag   = "${md5(file(var.build_path))}"
  count  = "${length(var.s3_key) > 0 ? 0 : 1}"
}

data "aws_s3_bucket_object" "loaded" {
  bucket = "${var.s3_bucket}"
  key = "${var.s3_key}"
  count  = "${length(var.s3_key) > 0 ? 1 : 0}"
}

resource "aws_lambda_function" "lambda" {
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${element(concat(data.aws_s3_bucket_object.loaded.*.key, aws_s3_bucket_object.object.*.key), 0)}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.lambda_iam_role.arn}"
  handler       = "${var.handler}"
  runtime       = "${var.runtime}"
  memory_size   = "${var.memory_size}"
  timeout       = "${var.timeout}"
  description   = "${var.description}"
  publish = false
  source_code_hash = "${base64sha256(file(var.build_path))}"

//  vpc_config {
//      security_group_ids = [ "${var.vpc_config["security_group_ids"]}" ]
//      subnet_ids = [ "${var.vpc_config["subnet_ids"]}" ]
//  }

  environment {
    variables = "${var.function_variables}"
  }
}

data "external" "alias" {
  program = ["${path.module}/alias.sh", "${aws_lambda_function.lambda.function_name}"]
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "${var.alias}"
  function_name    = "${aws_lambda_function.lambda.arn}"
  function_version = "${lookup(data.external.alias.result, var.alias, aws_lambda_function.lambda.version)}"
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

output "lambda_name" {
  value = "${aws_lambda_function.lambda.function_name}"
}

output "alias_arn" {
  value = "${aws_lambda_alias.lambda_alias.arn}"
}

output "s3_key" {
  value = "${element(concat(data.aws_s3_bucket_object.loaded.*.key, aws_s3_bucket_object.object.*.key), 0)}"
}
