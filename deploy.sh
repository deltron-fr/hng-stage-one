#!/bin/bash

set -e

LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
trap 'echo "Error on line $LINENO. Check $LOGFILE for details."; exit 1' ERR

read -p "Enter GitHub repo URL: " url
read -p "Enter GitHub Personal Access Token: " pat

read -p "Enter remote server username: " username
read -p "Enter remote server IP: " serverIP
read -p "Enter branch name (default: main): " branch
branch=${branch:-main}
read -p "Enter path to SSH private key: " ssh_key_path
read -p "Enter app port: " port


if [[ -z "$url" || -z "$pat" || -z "$username" || -z "$serverIP" || -z "$ssh_key_path" || -z "$port" ]]; then
	echo "Missing required arguments."
	exit 1
fi

if ! [[ -f "$ssh_key_path" ]]; then
	echo "ssh key file does not exist."
	exit 1
fi

repo_url=$(basename -s .git "$url")

clone_repo() {
	url_with_pat=$(echo "$url" | sed "s#https://#https://x-access-token:${pat}@#")

	if [[ -d "$repo_url" ]]; then
		echo "repository already exists. pulling changes..."
		cd "$repo_url" && git pull
		git checkout "$branch"
	else
		echo "cloning repo.."
		git clone -b "$branch" "$url_with_pat" "$repo_url"
		cd "$repo_url"
	fi
}
clone_repo


if ! [[ -f "Dockerfile" || -f "docker-compose.yaml" || -f "docker-compose.yml" ]]; then
	echo "no dockerfile or docker compose file."
	exit 1
else
	echo "docker file exists."	
fi

test_connectivity() {
	echo "testing connectivity..."

	ssh -i "$ssh_key_path" "$username"@"$serverIP" "exit"

}
test_connectivity

remote_actions() {
	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo apt update -y && sudo apt install -y ca-certificates curl gnupg lsb-release && sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo apt update -y && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && sudo docker --version && sudo docker compose version; exit"
	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo usermod -aG docker $username"
	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo apt install nginx -y && sudo systemctl start nginx && sudo systemctl enable nginx && exit"
}
remote_actions

deploy_app() {
	
	cd ..
	rsync -avz -e "ssh -i $ssh_key_path" "$(pwd)/$repo_url" "$username@$serverIP:/home/$username"
	if ! [[ -f "docker-compose.yaml" || -f "docker-compose.yml" ]]; then
		ssh -i "$ssh_key_path" "$username"@"$serverIP" "docker ps -q | xargs -r docker stop"
		ssh -i "$ssh_key_path" "$username"@"$serverIP" "cd $repo_url && docker build -t newimage:latest . && docker run -dp $port:$port newimage"
	else
		ssh -i "$ssh_key_path" "$username"@"$serverIP" "docker compose down -v || true"
		ssh -i "$ssh_key_path" "$username"@"$serverIP" "docker compose up -d"
	fi

	ssh -i "$ssh_key_path" "$username@$serverIP" "curl -f http://localhost:$port || echo 'Warning: App not responding on port $port'"

}
deploy_app

configure_nginx() {
	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo touch /etc/nginx/sites-available/app"
	ssh -i "$ssh_key_path" "$username@$serverIP" "
  sudo bash -c '
    cd /etc/nginx/sites-available
    cat > app <<\"EOF\"
server {
    listen 80;
    listen [::]:80;
    server_name $serverIP;
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
'"

	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/ || true"
	ssh -i "$ssh_key_path" "$username"@"$serverIP" "sudo nginx -t && sudo systemctl restart nginx"
}
configure_nginx

validate_deployment() {
  echo "Validating deployment..."
  ssh -i "$ssh_key_path" "$username@$serverIP" "
    docker ps
    curl -f http://$serverIP && echo 'App responding' || echo 'App not responding'
  "
}
validate_deployment


if [[ "$1" -eq "--cleanup" ]]; then
	ssh -i "$ssh_key_path" "$username@$serverIP" "
    docker compose down -v || docker stop \$(docker ps -aq) || true
    sudo rm -rf /home/$username/$repo_url
    sudo rm /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app || true
    "
    exit 0
fi