provider "aws" {
  region = "us-east-1"
}
resource "aws_s3_bucket" "resume_website" {
  bucket = "bythebeach.store"
  acl    = "public-read"
  website {
    index_document = "index.html"
  }
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

output "s3_website_endpoint" {
  value = aws_s3_bucket.resume_website.website_endpoint
}

resource "aws_cloudfront_distribution" "resume_website" {
  wait_for_deployment = true
  origin {
    domain_name = aws_s3_bucket.resume_website.website_endpoint
    origin_id   = "CustomOrigin"

    custom_origin_config {
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1", "TLSv1.2"]
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
    }
  }


  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.resume_website.arn
    ssl_support_method  = "sni-only"
  }

  enabled          = true
  is_ipv6_enabled  = true
  retain_on_delete = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  aliases = ["resume.bythebeach.store", "bythebeach.store", "www.bythebeach.store"]

  default_cache_behavior {
    target_origin_id       = "CustomOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    forwarded_values {
      query_string = false
      headers      = ["*"]
      cookies {
        forward = "none"
      }
    }
  }
}
resource "aws_cloudfront_origin_access_identity" "resume_website" {
  comment = "OAI for resume website"
}

resource "aws_acm_certificate" "resume_website" {
  domain_name               = "bythebeach.store"
  subject_alternative_names = ["*.bythebeach.store"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}
# Create the Lambda function
resource "aws_lambda_function" "resume_website" {
  s3_bucket     = "my-resume-website-lambda"
  s3_key        = "lambda.zip"
  function_name = "handler"
  handler       = "index.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_s3_bucket_policy" "lambda_access" {
  bucket = "my-resume-website-lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaFunctionAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::my-resume-website-lambda",
        "arn:aws:s3:::my-resume-website-lambda/*"
      ]
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "allow_s3_access" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume_website.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.resume_website.arn
}



resource "aws_iam_role" "lambda_role" {
  name               = "my-resume-website-lambda-role"
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



resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name   = "my-resume-website-lambda-dynamodb-policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "${aws_dynamodb_table.resume_website.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_api_gateway_rest_api" "api" {
  count = "1"

  name = "API for my resume website"
  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_method" "api_root" {
  count = "1"

  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "api_root" {
  count = "1"

  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_rest_api.api[0].root_resource_id
  http_method = aws_api_gateway_method.api_root[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.resume_website.invoke_arn
}

resource "aws_api_gateway_resource" "api" {
  count = "1"

  rest_api_id = aws_api_gateway_rest_api.api[0].id
  parent_id   = aws_api_gateway_rest_api.api[0].root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "api" {
  count = "1"

  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_resource.api[0].id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "api" {
  count = "1"

  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_method.api[0].resource_id
  http_method = aws_api_gateway_method.api[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.resume_website.invoke_arn
}
data "aws_caller_identity" "current" {}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

resource "aws_lambda_permission" "apigw" {
  count = "1"

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume_website.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:us-east-1:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api[0].id}/*/*"
}


// copied from: https://github.com/carrot/terraform-api-gateway-cors-module/blob/master/main.tf
resource "aws_api_gateway_method" "resource_options" {
  count = "1"

  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_resource.api[0].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "resource_options_integration" {
  count = "1"

  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_resource.api[0].id
  http_method = aws_api_gateway_method.resource_options[0].http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = <<PARAMS
{ "statusCode": 200 }
PARAMS
  }
}

resource "aws_api_gateway_integration_response" "resource_options_integration_response" {
  count = "1"

  depends_on  = [aws_api_gateway_integration.resource_options_integration[0]]
  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_resource.api[0].id
  http_method = aws_api_gateway_method.resource_options[0].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS,GET,PUT,PATCH,DELETE'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
resource "aws_api_gateway_method_response" "cors_headers" {
  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_resource.api[0].id
  http_method = "ANY"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}
resource "aws_api_gateway_integration_response" "cors_headers" {
  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_resource.api[0].id
  http_method = "ANY"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'*'"
  }
}
resource "aws_api_gateway_method_response" "resource_options_200" {
  count = "1"

  depends_on      = [aws_api_gateway_method.resource_options[0]]
  rest_api_id     = aws_api_gateway_rest_api.api[0].id
  resource_id     = aws_api_gateway_resource.api[0].id
  http_method     = "OPTIONS"
  status_code     = "200"
  response_models = { "application/json" = "Empty" }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_deployment" "api" {
  count = "1"

  depends_on  = [aws_api_gateway_integration_response.resource_options_integration_response[0], aws_api_gateway_integration.api[0]]
  rest_api_id = aws_api_gateway_rest_api.api[0].id
  stage_name  = "dev1"
}

resource "aws_route53_zone" "resume_website" {
  name = "bythebeach.store"
}

resource "aws_route53_record" "resume_website" {
  zone_id = aws_route53_zone.resume_website.zone_id
  name    = "resume.bythebeach.store"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.resume_website.domain_name
    zone_id                = aws_cloudfront_distribution.resume_website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_dynamodb_table" "resume_website" {
  name           = "my-resume-website-table"
  billing_mode   = "PROVISIONED"
  write_capacity = 5
  read_capacity  = 5

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "visit_count"
    type = "N"
  }

  hash_key  = "pk"
  range_key = "sk"

  global_secondary_index {
    name            = "visit_count_index"
    hash_key        = "visit_count"
    range_key       = "sk"
    projection_type = "ALL"
    write_capacity  = 5
    read_capacity   = 5
  }
}
