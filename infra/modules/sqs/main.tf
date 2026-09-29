# Messages that keep failing end up here instead of being retried forever
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-click-events-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum, to give time to investigate
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "click_events" {
  name                       = "${var.project}-click-events"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # long polling by default, matching the worker
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}