#!/usr/bin/env bash
# ============================================================
#  DevOps / Platform / AI-Infra workstation setup for Ubuntu LTS
#  Target: ThinkPad T490 (x86_64)
#  Run as your normal user:  ./setup-devops.sh
#  Safe to re-run: steps skip or update what's already installed.
# ============================================================
set -euo pipefail

ARCH="amd64"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not with sudo. It will ask for your password when needed."
  exit 1
fi

# Ask for sudo once and keep it alive while the script runs
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ------------------------------------------------------------
log "1/12  Updating the system"
sudo apt update
sudo apt upgrade -y

# ------------------------------------------------------------
log "2/12  Installing essential tools"
sudo apt install -y \
  build-essential make curl wget git vim tmux htop tree jq unzip zip \
  ca-certificates gnupg lsb-release software-properties-common apt-transport-https \
  net-tools dnsutils iputils-ping traceroute nmap openssh-client \
  python3 python3-pip python3-venv pipx shellcheck bash-completion \
  timeshift

# ------------------------------------------------------------
log "3/12  Configuring Git"
if [[ -z "$(git config --global user.name || true)" ]]; then
  read -rp "Your full name for Git commits: " GIT_NAME
  git config --global user.name "$GIT_NAME"
fi
if [[ -z "$(git config --global user.email || true)" ]]; then
  read -rp "Your GitHub email address: " GIT_EMAIL
  git config --global user.email "$GIT_EMAIL"
fi
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor vim

# ------------------------------------------------------------
log "4/12  Creating an SSH key for GitHub"
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
  echo "You'll be asked for a passphrase (recommended). Press Enter twice to skip."
  ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$HOME/.ssh/id_ed25519"
else
  echo "SSH key already exists, skipping."
fi

# ------------------------------------------------------------
log "5/12  Installing Docker Engine (official repo)"
if ! have docker; then
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "Docker already installed, skipping."
fi
sudo usermod -aG docker "$USER"   # lets you run docker without sudo (after re-login)

# ------------------------------------------------------------
log "6/12  Installing kubectl (latest stable)"
K8S_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo "$TMP/kubectl" "https://dl.k8s.io/release/${K8S_VER}/bin/linux/${ARCH}/kubectl"
sudo install -m 0755 "$TMP/kubectl" /usr/local/bin/kubectl
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl >/dev/null

# ------------------------------------------------------------
log "7/12  Installing kind, Helm and k9s"
KIND_VER="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r .tag_name)"
curl -fsSLo "$TMP/kind" "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-${ARCH}"
sudo install -m 0755 "$TMP/kind" /usr/local/bin/kind

HELM_VER="$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | jq -r .tag_name)"
curl -fsSL "https://get.helm.sh/helm-${HELM_VER}-linux-${ARCH}.tar.gz" | tar -xz -C "$TMP"
sudo install -m 0755 "$TMP/linux-${ARCH}/helm" /usr/local/bin/helm

curl -fsSLo "$TMP/k9s.deb" "https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${ARCH}.deb"
sudo apt install -y "$TMP/k9s.deb"

# ------------------------------------------------------------
log "8/12  Installing Terraform (latest)"
TF_VER="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"
curl -fsSLo "$TMP/terraform.zip" "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_${ARCH}.zip"
unzip -oq "$TMP/terraform.zip" -d "$TMP/tf"
sudo install -m 0755 "$TMP/tf/terraform" /usr/local/bin/terraform

# ------------------------------------------------------------
log "9/12  Installing AWS CLI v2"
curl -fsSLo "$TMP/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -q "$TMP/awscliv2.zip" -d "$TMP"
sudo "$TMP/aws/install" --update

# ------------------------------------------------------------
log "10/12 Installing Go (needed for most CNCF projects)"
GO_VER="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
sudo rm -rf /usr/local/go
curl -fsSL "https://go.dev/dl/${GO_VER}.linux-${ARCH}.tar.gz" | sudo tar -C /usr/local -xz

# ------------------------------------------------------------
log "11/12 Installing Ansible (via pipx) and VS Code"
pipx ensurepath
pipx install --include-deps ansible || pipx upgrade ansible
sudo snap install code --classic || true

# ------------------------------------------------------------
log "12/12 Shell setup (PATH and aliases)"
BASHRC="$HOME/.bashrc"
grep -q '# >>> devops-setup >>>' "$BASHRC" || cat >> "$BASHRC" <<'EOF'

# >>> devops-setup >>>
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin:$HOME/.local/bin"
alias k=kubectl
complete -o default -F __start_kubectl k
# <<< devops-setup <<<
EOF

# ------------------------------------------------------------
log "Done! Installed versions:"
export PATH="$PATH:/usr/local/go/bin:$HOME/.local/bin"
printf '%-12s %s\n' "git"       "$(git --version)"
printf '%-12s %s\n' "docker"    "$(docker --version)"
printf '%-12s %s\n' "kubectl"   "$(kubectl version --client 2>/dev/null | head -n1)"
printf '%-12s %s\n' "kind"      "$(kind version)"
printf '%-12s %s\n' "helm"      "$(helm version --short)"
printf '%-12s %s\n' "k9s"       "$(k9s version --short 2>/dev/null | head -n1 || echo installed)"
printf '%-12s %s\n' "terraform" "$(terraform version | head -n1)"
printf '%-12s %s\n' "aws"       "$(aws --version)"
printf '%-12s %s\n' "go"        "$(go version)"
printf '%-12s %s\n' "ansible"   "$(ansible --version 2>/dev/null | head -n1 || echo 'open a new terminal to use')"

echo
echo ">>> IMPORTANT: Log out and log back in (or reboot) so Docker works without sudo."
echo ">>> Then add this SSH key to GitHub (Settings -> SSH and GPG keys):"
echo
cat "$HOME/.ssh/id_ed25519.pub"
