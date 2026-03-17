#!/bin/bash
set -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================="
echo "Starting user-data script at $(date)"
echo "========================================="

# Variables passed from Terraform
DOCKER_IMAGE="${DOCKER_IMAGE}"
S3_BUCKET="${S3_BUCKET}"
ENVIRONMENT="${ENVIRONMENT}"
AWS_REGION="${AWS_REGION}"

echo "DOCKER_IMAGE = $DOCKER_IMAGE"
echo "S3_BUCKET = $S3_BUCKET"
echo "ENVIRONMENT = $ENVIRONMENT"
echo "AWS_REGION = $AWS_REGION"

# Update system
echo "Updating system..."
yum update -y

# Install Docker
echo "Installing Docker..."
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install AWS CLI v2
echo "Installing AWS CLI..."
yum install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Login to ECR
echo "Logging into ECR..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Pull Docker image
echo "Pulling Docker image: $DOCKER_IMAGE"
docker pull $DOCKER_IMAGE

# ========== TÉLÉCHARGEMENT DES MODÈLES ==========
echo "Creating models directory..."
mkdir -p /app/models

echo "Downloading models from S3..."
aws s3 cp s3://$S3_BUCKET/models/ /app/models/ --recursive || echo "Warning: Model download failed, continuing anyway..."

# ========== TÉLÉCHARGEMENT DES DONNÉES DE SCÉNARIOS ==========
echo "Creating data directory..."
mkdir -p /app/data/test

echo "Downloading scenario data from S3..."
# Essayer différents chemins possibles
if aws s3 ls s3://$S3_BUCKET/models/scenario_windows.pkl; then
    aws s3 cp s3://$S3_BUCKET/models/scenario_windows.pkl /app/data/test/ && echo "✅ Scenario data downloaded from models/"
elif aws s3 ls s3://$S3_BUCKET/scenario_windows.pkl; then
    aws s3 cp s3://$S3_BUCKET/scenario_windows.pkl /app/data/test/ && echo "✅ Scenario data downloaded from root"
elif aws s3 ls s3://$S3_BUCKET/data/test/scenario_windows.pkl; then
    aws s3 cp s3://$S3_BUCKET/data/test/scenario_windows.pkl /app/data/test/ && echo "✅ Scenario data downloaded from data/test/"
else
    echo "⚠️ Scenario data not found in S3"
fi

# ========== VÉRIFICATION DES FICHIERS ==========
echo "=== Models downloaded ==="
ls -la /app/models/anodet_models/ 2>/dev/null || echo "No anodet_models found"
ls -la /app/models/rul_models/ 2>/dev/null || echo "No rul_models found"
echo "=== Scenario data ==="
ls -la /app/data/test/ 2>/dev/null || echo "No scenario data found"

# ========== LANCEMENT DU CONTENEUR ==========
# Stop any existing container
docker stop engine-health-app || true
docker rm engine-health-app || true

echo "Starting container with model and data volumes..."
docker run -d \
    --name engine-health-app \
    --restart always \
    -p 5000:5000 \
    -e S3_BUCKET=$S3_BUCKET \
    -e ENVIRONMENT=$ENVIRONMENT \
    -e AWS_REGION=$AWS_REGION \
    -v /app/models:/app/models \
    -v /app/data:/app/data \
    $DOCKER_IMAGE

# Check if container is running
sleep 5
echo "Container status:"
docker ps -a | grep engine-health-app
echo "Container logs:"
docker logs engine-health-app --tail 30

# Test locally
echo "Testing application locally..."
curl -s http://localhost:5000/health || echo "Health check failed - check logs above"

echo "========================================="
echo "User data script completed at $(date)"
echo "========================================="
