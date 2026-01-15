# Scenario 2: APIs as a Product - Public and Private APIs

## Current Architecture

As shown in the diagram:
- All API traffic flows through `api.allianz-trade.com`
- Path: CloudFront → WAF Global + Shield Advanced → WAF Regional → API Gateway → Lambda/ALB+ECS
- All APIs are currently public by design
- Authentication via Lambda Authorizer

---

## Question 1: What weaknesses can you see on the current architecture?

### Security Weaknesses

1. **Internal APIs exposed to internet**: Services that only need internal access are unnecessarily exposed through CloudFront. This increases attack surface.

2. **No network segmentation**: Internal and external traffic follow the same path, making it harder to isolate issues.

3. **Regional API Gateway endpoints are public**: Attackers could potentially bypass CloudFront/WAF and access API Gateway directly.

### Operational Weaknesses

1. **Unnecessary costs**: Internal traffic pays for CloudFront and WAF when it doesn't need to.

2. **Added latency**: Internal service-to-service calls route through the internet instead of staying within AWS network.

3. **Troubleshooting complexity**: When issues occur, it's harder to determine if the problem is internal or external traffic.

---

## Question 2: We would like to change the exposition of these APIs to have public and private APIs. What would the new architecture be?

### New Architecture: Separate Public and Private Paths

```
EXTERNAL TRAFFIC (customers, brokers):
Internet → CloudFront → WAF → Regional API Gateway → Lambda Authorizer → Backend

INTERNAL TRAFFIC (internal services):
VPC → VPC Endpoint → Private API Gateway → IAM Auth → Backend
```

### Implementation

```hcl
# Private API Gateway - only accessible from VPC
resource "aws_api_gateway_rest_api" "private_api" {
  name = "internal-api"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.api_gateway.id]
  }
}

# VPC Endpoint for internal services
resource "aws_vpc_endpoint" "api_gateway" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true
}

# Policy restricting access to VPC Endpoint only
resource "aws_api_gateway_rest_api_policy" "private_policy" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "execute-api:Invoke"
      Resource  = "${aws_api_gateway_rest_api.private_api.execution_arn}/*"
      Condition = {
        StringEquals = {
          "aws:sourceVpce" = aws_vpc_endpoint.api_gateway.id
        }
      }
    }]
  })
}
```

---

## Question 3: In the current architecture, how could CloudFront be configured to route traffic to multiple API Gateways based on path?

### CloudFront Path-Based Routing Configuration

```hcl
resource "aws_cloudfront_distribution" "api_distribution" {
  enabled = true

  # Origin for /customers/*
  origin {
    domain_name = "${aws_api_gateway_rest_api.customers_api.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "customers-api"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin for /brokers/*
  origin {
    domain_name = "${aws_api_gateway_rest_api.brokers_api.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "brokers-api"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "customers-api"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin", "Accept"]
      cookies { forward = "none" }
    }
  }

  # /brokers/* routes to brokers API
  ordered_cache_behavior {
    path_pattern           = "/brokers/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "brokers-api"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin", "Accept"]
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
```

CloudFront evaluates `ordered_cache_behavior` blocks in order and uses the first matching pattern.

---

## Question 4: If we want to protect our regional API Gateway endpoints from traffic that "bypasses" CloudFront/WAF, how could we achieve this?

### Solution 1: Secret Header Validation

CloudFront adds a secret header, API Gateway only accepts requests with it:

```hcl
# API Gateway policy requiring secret header
resource "aws_api_gateway_rest_api_policy" "restrict_to_cloudfront" {
  rest_api_id = aws_api_gateway_rest_api.public_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "execute-api:Invoke"
      Resource  = "${aws_api_gateway_rest_api.public_api.execution_arn}/*"
      Condition = {
        StringEquals = {
          "aws:Referer" = var.cloudfront_secret_header
        }
      }
    }]
  })
}

# CloudFront injects secret header
resource "aws_cloudfront_distribution" "api" {
  origin {
    domain_name = "${aws_api_gateway_rest_api.public_api.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "api-gateway"

    custom_header {
      name  = "Referer"
      value = var.cloudfront_secret_header  # Store in Secrets Manager
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
}
```

### Solution 2: WAF on API Gateway filtering by CloudFront IPs

```hcl
resource "aws_wafv2_web_acl" "apigw_waf" {
  name  = "apigw-protection"
  scope = "REGIONAL"

  default_action { block {} }

  rule {
    name     = "allow-cloudfront-only"
    priority = 1
    action { allow {} }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.cloudfront_ips.arn
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "CloudFrontOnly"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "apigw-waf"
  }
}

resource "aws_wafv2_web_acl_association" "apigw" {
  resource_arn = aws_api_gateway_stage.prod.arn
  web_acl_arn  = aws_wafv2_web_acl.apigw_waf.arn
}
```

**Note**: CloudFront IPs change periodically - implement automation to update the IP set when AWS publishes changes.

### Recommendation

Combine both solutions: secret header for simplicity + WAF IP filtering for defense in depth.
