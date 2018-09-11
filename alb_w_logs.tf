resource "aws_lb" "application" {
  load_balancer_type               = "application"
  name                             = "${var.load_balancer_name}"
  internal                         = "${var.load_balancer_is_internal}"
  security_groups                  = ["${var.security_groups}"]
  subnets                          = ["${var.subnets}"]
  idle_timeout                     = "${var.idle_timeout}"
  enable_cross_zone_load_balancing = "${var.enable_cross_zone_load_balancing}"
  enable_deletion_protection       = "${var.enable_deletion_protection}"
  enable_http2                     = "${var.enable_http2}"
  ip_address_type                  = "${var.ip_address_type}"
  tags                             = "${merge(var.tags, map("Name", var.load_balancer_name))}"

  access_logs {
    enabled = true
    bucket  = "${var.log_bucket_name}"
    prefix  = "${var.log_location_prefix}"
  }

  timeouts {
    create = "${var.load_balancer_create_timeout}"
    delete = "${var.load_balancer_delete_timeout}"
    update = "${var.load_balancer_update_timeout}"
  }

  count = "${var.logging_enabled ? 1 : 0}"
}

resource "aws_lb_target_group" "main" {
  name                 = "${lookup(var.target_groups[count.index], "name")}"
  vpc_id               = "${var.vpc_id}"
  port                 = "${lookup(var.target_groups[count.index], "backend_port")}"
  protocol             = "${upper(lookup(var.target_groups[count.index], "backend_protocol"))}"
  deregistration_delay = "${lookup(var.target_groups[count.index], "deregistration_delay", lookup(var.target_groups_defaults, "deregistration_delay"))}"
  target_type          = "${lookup(var.target_groups[count.index], "target_type", lookup(var.target_groups_defaults, "target_type"))}"

  health_check {
    interval            = "${lookup(var.target_groups[count.index], "health_check_interval", lookup(var.target_groups_defaults, "health_check_interval"))}"
    path                = "${lookup(var.target_groups[count.index], "health_check_path", lookup(var.target_groups_defaults, "health_check_path"))}"
    port                = "${lookup(var.target_groups[count.index], "health_check_port", lookup(var.target_groups_defaults, "health_check_port"))}"
    healthy_threshold   = "${lookup(var.target_groups[count.index], "health_check_healthy_threshold", lookup(var.target_groups_defaults, "health_check_healthy_threshold"))}"
    unhealthy_threshold = "${lookup(var.target_groups[count.index], "health_check_unhealthy_threshold", lookup(var.target_groups_defaults, "health_check_unhealthy_threshold"))}"
    timeout             = "${lookup(var.target_groups[count.index], "health_check_timeout", lookup(var.target_groups_defaults, "health_check_timeout"))}"
    protocol            = "${upper(lookup(var.target_groups[count.index], "healthcheck_protocol", lookup(var.target_groups[count.index], "backend_protocol")))}"
    matcher             = "${lookup(var.target_groups[count.index], "health_check_matcher", lookup(var.target_groups_defaults, "health_check_matcher"))}"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = "${lookup(var.target_groups[count.index], "cookie_duration", lookup(var.target_groups_defaults, "cookie_duration"))}"
    enabled         = "${lookup(var.target_groups[count.index], "stickiness_enabled", lookup(var.target_groups_defaults, "stickiness_enabled"))}"
  }

  tags       = "${merge(var.tags, map("Name", lookup(var.target_groups[count.index], "name")))}"
  count      = "${var.logging_enabled ? var.target_groups_count : 0}"
  depends_on = ["aws_lb.application"]

  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_lb_listener" "frontend_http_tcp" {
#   load_balancer_arn = "${element(concat(aws_lb.application.*.arn, aws_lb.application_no_logs.*.arn), 0)}"
#   port              = "${lookup(var.http_tcp_listeners[count.index], "port")}"
#   protocol          = "${lookup(var.http_tcp_listeners[count.index], "protocol")}"
#   count             = "${var.logging_enabled ? var.http_tcp_listeners_count : 0}"

#   default_action {
#     target_group_arn = "${aws_lb_target_group.main.*.id[lookup(var.http_tcp_listeners[count.index], "target_group_index", 0)]}"
#     type             = "forward"
#   }
# }

resource "aws_lb_listener" "frontend_http_tcp" {
  load_balancer_arn = "${element(concat(aws_lb.application_no_logs.*.arn, list("")), 0)}"
  port              = "${lookup(var.http_tcp_listeners[count.index], "port")}"
  protocol          = "${lookup(var.http_tcp_listeners[count.index], "protocol")}"
  count             = "${var.logging_enabled && var.enable_http_tcp_listener_redirect ? 0 : var.http_tcp_listeners_count}"

  default_action {
    target_group_arn = "${aws_lb_target_group.main_no_logs.*.id[lookup(var.http_tcp_listeners[count.index], "target_group_index", 0)]}"
    type             = "${lookup(var.http_tcp_listeners[count.index], "default_action_type", "forward")}"

    redirect {
      count       = "${lookup(var.http_tcp_listeners[count.index], "default_action_type") == "redirect" ? 1 : 0}"
      host        = "${lookup(var.http_tcp_listeners[count.index], "default_action_redirect_host", lookup(var.http_tcp_listeners_redirect_defaults, "host"))}"
      path        = "${lookup(var.http_tcp_listeners[count.index], "default_action_redirect_path", lookup(var.http_tcp_listeners_redirect_defaults, "path"))}"
      port        = "${lookup(var.http_tcp_listeners[count.index], "default_action_redirect_port", lookup(var.http_tcp_listeners_redirect_defaults, "port"))}"
      protocol    = "${lookup(var.http_tcp_listeners[count.index], "default_action_redirect_protocol", lookup(var.http_tcp_listeners_redirect_defaults, "protocol"))}"
      query       = "${lookup(var.http_tcp_listeners[count.index], "default_action_redirect_query", lookup(var.http_tcp_listeners_redirect_defaults, "query"))}"
      status_code = "${lookup(var.http_tcp_listeners[count.index], "default_action_redirect_status_code", lookup(var.http_tcp_listeners_redirect_defaults, "status_code"))}"
    }
  }
}

resource "aws_lb_listener" "frontend_https" {
  load_balancer_arn = "${element(concat(aws_lb.application.*.arn, aws_lb.application_no_logs.*.arn), 0)}"
  port              = "${lookup(var.https_listeners[count.index], "port")}"
  protocol          = "HTTPS"
  certificate_arn   = "${lookup(var.https_listeners[count.index], "certificate_arn")}"
  ssl_policy        = "${lookup(var.https_listeners[count.index], "ssl_policy", var.listener_ssl_policy_default)}"
  count             = "${var.logging_enabled ? var.https_listeners_count : 0}"

  default_action {
    target_group_arn = "${aws_lb_target_group.main.*.id[lookup(var.https_listeners[count.index], "target_group_index", 0)]}"
    type             = "${lookup(var.https_listeners[count.index], "default_action_type", "forward")}"

    redirect {
      count       = "${lookup(var.https_listeners[count.index], "default_action_type") == "redirect" ? 1 : 0}"
      host        = "${lookup(var.https_listeners[count.index], "default_action_redirect_host", lookup(var.default_action_redirect_defaults, "host"))}"
      path        = "${lookup(var.https_listeners[count.index], "default_action_redirect_path", lookup(var.default_action_redirect_defaults, "path"))}"
      port        = "${lookup(var.https_listeners[count.index], "default_action_redirect_port", lookup(var.default_action_redirect_defaults, "port"))}"
      protocol    = "${lookup(var.https_listeners[count.index], "default_action_redirect_protocol", lookup(var.default_action_redirect_defaults, "protocol"))}"
      query       = "${lookup(var.https_listeners[count.index], "default_action_redirect_query", lookup(var.default_action_redirect_defaults, "query"))}"
      status_code = "${lookup(var.https_listeners[count.index], "default_action_redirect_status_code", lookup(var.default_action_redirect_defaults, "status_code"))}"
    }
  }
}

resource "aws_lb_listener_certificate" "https_listener" {
  listener_arn    = "${aws_lb_listener.frontend_https.*.arn[lookup(var.extra_ssl_certs[count.index], "https_listener_index")]}"
  certificate_arn = "${lookup(var.extra_ssl_certs[count.index], "certificate_arn")}"
  count           = "${var.logging_enabled ? var.extra_ssl_certs_count : 0}"
}
