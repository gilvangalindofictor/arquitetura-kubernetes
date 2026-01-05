# LocalStack Development Environment

This directory contains all the necessary configurations to run the entire observability platform locally using [LocalStack](https://localstack.cloud/).

This allows for a complete, cost-free development and testing loop without needing a real AWS account.

## How it Works

We will use Docker Compose to start a LocalStack container with the required AWS services enabled (EKS, S3, IAM). A custom initialization script (`init-localstack.sh`) will then use the AWS CLI (against the local container) to prepare the environment (e.g., create S3 buckets).

After initialization, you can use Terraform and Helm (pointed to the local services) to deploy the platform, just as you would in a real AWS environment.

## Step-by-Step Guide

### 1. Start LocalStack

First, start the LocalStack container using Docker Compose.

```bash
# From the /localstack directory
docker-compose up -d
```

Wait a minute for the services to become available. You can check the logs with `docker-compose logs -f`.

### 2. Initialize the Local Environment

Run the initialization script. This script configures an AWS CLI profile named `localstack` and creates the necessary S3 buckets inside the container.

```bash
# Make sure the script is executable
chmod +x init-localstack.sh

# Run the script
./init-localstack.sh
```

### 3. Deploy the Infrastructure (Terraform)

Now, apply the Terraform configuration using the LocalStack provider settings.

```bash
# Navigate to the Terraform directory
cd ../infra/terraform

# Initialize Terraform
terraform init

# Apply the configuration, targeting the localstack provider
# The -var="aws_profile=localstack" is crucial here
terraform apply -var="aws_profile=localstack" --auto-approve
```

This will provision an "EKS" cluster (a K3s cluster managed by LocalStack), IAM roles, and S3 buckets inside your LocalStack container.

### 4. Configure `kubectl`

Point your `kubectl` to the new local cluster. The `init-localstack.sh` script already configured the `localstack` AWS profile, which is needed for the next command.

```bash
# This command is also provided in the output of 'terraform apply'
aws eks --region us-east-1 update-kubeconfig --name observabilidade-cluster --profile localstack
```
**Note:** The LocalStack EKS endpoint runs on a random port on your host. The `update-kubeconfig` command handles this automatically.

### 5. Deploy the Observability Stack (Helm)

With `kubectl` configured, deploy the observability stack using the LocalStack-specific `values.yaml` files.

```bash
# Navigate to the Helm directory
cd ../helm

# Create the namespace
kubectl create namespace observability

# Install the charts using the -localstack.yaml value files
helm install otel-collector ./opentelemetry-collector -n observability
helm install prometheus-stack ./kube-prometheus-stack -n observability
helm install loki ./loki -f loki/values-localstack.yaml -n observability
helm install tempo ./tempo -f tempo/values-localstack.yaml -n observability
```

### 6. Access Grafana

Forward the Grafana port to access the UI.

```bash
kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n observability
```

Open [http://localhost:3000](http://localhost:3000) in your browser. The user is `admin` and the password is `changeme-in-production`. The Loki and Tempo datasources should be pre-configured and working.
