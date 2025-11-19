
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    random = { source = "hashicorp/random" }
  }
}
data "coder_workspace_owner" "me" {}

data "coder_provisioner" "me" {}
provider "docker" {}
data "coder_workspace" "me" {}


module "filebrowser" {
  source   = "registry.coder.com/modules/filebrowser/coder"
  version  = "1.0.8"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/www"
  database_path = "/home/coder/filebrowser.db"
}



resource "coder_app" "phpmyadmin" {
  agent_id     = coder_agent.main.id
  slug         = "phpmyadmin"
  display_name = "PHPMyAdmin"
  url          = "http://localhost:4443/phpmyadmin"
  subdomain    = true
}

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

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  #startup_script = "/usr/local/bin/start.sh"
    startup_script         = <<-EOT

    # install and start code-server
    /usr/local/bin/start.sh &
    sleep 100
  EOT
  dir            = "/home/coder/www"

  env = {
  GIT_AUTHOR_NAME     = data.coder_workspace_owner.me.name
  GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
  GIT_COMMITTER_NAME  = data.coder_workspace_owner.me.name
  GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  GITHUB_TOKEN        = ""
}

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
    script       = "coder stat disk --path /home/coder/www"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script = <<EOT
echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script = <<EOT
free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
EOT
    interval     = 10
    timeout      = 1
  }
}



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


resource "docker_container" "mysql" {
  name  = "coder-${data.coder_workspace.me.name}-mysql"
  image = "mariadb:10"
  depends_on = [docker_volume.mysql_data]

  env = [
    "MYSQL_ROOT_PASSWORD=${random_password.mysql_password.result}",
    "MYSQL_DATABASE=${random_pet.mysql_db.id}",
    "MYSQL_USER=${random_pet.mysql_user.id}",
    "MYSQL_PASSWORD=${random_password.mysql_password.result}"
  ]

  volumes {
    container_path = "/var/lib/mysql"
    volume_name    = docker_volume.mysql_data.name
    read_only      = false
  }

  networks_advanced {
    name = docker_network.private_network.name
  }

  labels {
    label = "coder.service"
    value = "mysql"
  }
}

resource "docker_volume" "mysql_data" {
  name = "coder-${data.coder_workspace.me.name}-mysql-data"
}


resource "docker_image" "main" {
  name = data.coder_workspace.me.name

  build {
    context = "./build"
    build_args = {
      USER = "coder"
      WORKDIR = "/home/coder/www"
    }
  }

  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_network" "private_network" {
  name = "coder-${data.coder_workspace.me.name}-network"
}

resource "docker_container" "dind" {
  image      = "docker:dind"
  privileged = true
  name = "coder-dind-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"


  entrypoint = ["dockerd", "-H", "tcp://0.0.0.0:2375"]

  networks_advanced {
    name = docker_network.private_network.name
  }
}



resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image = docker_image.main.name
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  #entrypoint = ["/bin/bash","/usr/local/bin/start.sh"]  # <- AICI este esențial
    # Folosește command ca să ruleze scriptul tău custom
   #command = ["bash", "-c", "ls -l /usr/local/bin/start.sh && /usr/local/bin/start.sh"]
  #entrypoint = ["coder", "agent || sleep 40"] # ← lasă agentul să se ocupe de tot
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]



  env = [
    "WORKDIR=/home/coder/www",
    
    "DOCKER_HOST=${docker_container.dind.name}:2375",
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "CODER_AGENT_URL=wss://cp.pdev.ro",
    "CODER_AGENT_AUTH=token",
 "MYSQL_HOST=${docker_container.mysql.name}",
    "MYSQL_PORT=3306",
    "MYSQL_DATABASE=${random_pet.mysql_db.id}",
    "MYSQL_USER=${random_pet.mysql_user.id}",
    "MYSQL_PASSWORD=${random_password.mysql_password.result}"


  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  networks_advanced {
    name = docker_network.private_network.name
  }

  volumes {
    container_path = "/home/coder/www"
    volume_name    = "coder-${data.coder_workspace.me.name}-project"
    read_only      = false
  }

  volumes {
    container_path = "/var/lib/mysql"
    volume_name    = docker_volume.mysql_data.name
    read_only      = false
  }



  volumes {
    container_path = "/home/coder"
    volume_name    = "coder-${data.coder_workspace.me.name}-home"
    read_only      = false
  }

  labels {
  label = "coder.owner"
  value = data.coder_workspace_owner.me.name
}
labels {
  label = "coder.owner_id"
  value = data.coder_workspace_owner.me.id
}

  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }

  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }

  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }

  lifecycle {
    ignore_changes = all
  }
}
