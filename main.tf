terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "coder" {}
provider "kubernetes" {
  # Se presupune că Coder rulează în cluster sau are acces via ~/.kube/config
  # Lăsăm config_path gol pentru a folosi default-ul (in-cluster sau local)
  # config_path = "~/.kube/config" 
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# --- Persistent Volumes ---

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.name)}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "app.kubernetes.io/managed-by" = "coder"
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mysql" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.name)}-mysql"
    namespace = var.namespace
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

# --- Passwords & Secrets ---

resource "random_password" "mysql_password" {
  length  = 16
  special = false
}

resource "random_pet" "mysql_user" {
  length = 1
}

resource "random_pet" "mysql_db" {
  length = 1
}

# --- Coder Agent ---

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  dir            = "/home/coder/www"
  
  # Scriptul de startup rulează scriptul tău custom și pornește code-server
  startup_script = <<-EOT
    # Rulează scriptul de configurare (permisiuni, apache restart etc.)
    /usr/local/bin/start.sh &
  EOT

  env = {
    GIT_AUTHOR_NAME     = data.coder_workspace_owner.me.name
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = data.coder_workspace_owner.me.name
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }
  
  # Display useful metadata in Coder dashboard
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }
}

# --- Apps ---

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code Web"
  url          = "http://localhost:13337/?folder=/home/coder/www"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "phpmyadmin" {
  agent_id     = coder_agent.main.id
  slug         = "phpmyadmin"
  display_name = "PHPMyAdmin"
  url          = "http://localhost:80/phpmyadmin" 
  subdomain    = true
  share        = "owner"
}

resource "coder_app" "apache" {
  agent_id     = coder_agent.main.id
  slug         = "web"
  display_name = "Web Preview"
  url          = "http://localhost:80"
  subdomain    = true
  share        = "owner"
}

# --- Main Pod ---

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "app.kubernetes.io/managed-by" = "coder"
    }
  }

  spec {
    security_context {
      run_as_user = 1000 # coder user
      fs_group    = 1000
    }

    # Container 1: PHP/Apache Development Environment
    container {
      name    = "dev"
      image   = "ghcr.io/edward1987/k8s_coder_laravel:latest"
      image_pull_policy = "Always"
      
      command = ["sh", "-c", coder_agent.main.init_script]
      
      security_context {
        run_as_user = 1000
      }

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      
      # Environment variables for DB connection (Localhost because of sidecar)
      env {
        name  = "MYSQL_HOST"
        value = "127.0.0.1"
      }
      env {
        name  = "MYSQL_PORT"
        value = "3306"
      }
      env {
        name  = "MYSQL_DATABASE"
        value = random_pet.mysql_db.id
      }
      env {
        name  = "MYSQL_USER"
        value = random_pet.mysql_user.id
      }
      env {
        name  = "MYSQL_PASSWORD"
        value = random_password.mysql_password.result
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
        read_only  = false
      }
    }

    # Container 2: MariaDB Sidecar
    container {
      name  = "mysql"
      image = "mariadb:10"
      
      env {
        name  = "MYSQL_ROOT_PASSWORD"
        value = random_password.mysql_password.result
      }
      env {
        name  = "MYSQL_DATABASE"
        value = random_pet.mysql_db.id
      }
      env {
        name  = "MYSQL_USER"
        value = random_pet.mysql_user.id
      }
      env {
        name  = "MYSQL_PASSWORD"
        value = random_password.mysql_password.result
      }

      volume_mount {
        mount_path = "/var/lib/mysql"
        name       = "mysql-data"
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
      }
    }

    volume {
      name = "mysql-data"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.mysql.metadata.0.name
      }
    }
  }
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces)"
  default     = "default" 
}
