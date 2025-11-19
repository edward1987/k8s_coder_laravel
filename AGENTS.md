# Build, Lint & Test
- **Docker Build**: `docker build -t test-env .` to verify image construction.
- **Terraform Format**: `terraform fmt -check` to enforce HCL style.
- **Terraform Validate**: `terraform init -backend=false && terraform validate` to check configuration.
- **Shell Check**: `bash -n start.sh` to check syntax (or `shellcheck` if available).

# Code Style & Conventions
- **Terraform**:
  - Follow standard HCL formatting; always run `terraform fmt` before committing.
  - Use `snake_case` for resource names and variables.
  - Define infrastructure in `main.tf`; keep provider versions in `terraform` block.
- **Docker**:
  - Minimize layers; clean up apt caches in the same `RUN` instruction.
  - Use explicit versions for base images and packages (e.g., `php8.3`).
- **Shell**:
  - Ensure `#!/bin/bash` shebang.
  - Use meaningful comments for complex setup steps (e.g., NVM, permissions).
- **Security**:
  - Never hardcode credentials. Use `random_password` or input variables.
