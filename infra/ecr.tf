resource "aws_ecr_repository" "rest_server" {
  name                 = "${var.project_name}/rest-server"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "ortc_server" {
  name                 = "${var.project_name}/ortc-server"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "bench" {
  name                 = "${var.project_name}/bench"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}
