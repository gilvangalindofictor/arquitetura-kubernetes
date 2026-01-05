# Validation

This directory contains a script to validate that your local environment is correctly configured to deploy the observability platform.

## How to Use

1.  **Navigate to this directory**:
    ```bash
    cd infra/validation
    ```

2.  **Make the script executable**:
    ```bash
    chmod +x validate.sh
    ```

3.  **Run the script**:
    ```bash
    ./validate.sh
    ```

## What it Does

The `validate.sh` script performs the following checks:

1.  **Prerequisites Check**:
    -   Verifies that `aws`, `terraform`, `kubectl`, and `helm` are installed and available in your `PATH`.

2.  **AWS Configuration Check**:
    -   Runs `aws sts get-caller-identity` to ensure your AWS credentials are configured and valid.
    -   Displays the AWS Account ID it detects.

3.  **Terraform Validation**:
    -   Navigates to the `../terraform` directory.
    -   Runs `terraform init` to initialize the backend and download providers.
    -   Runs `terraform validate` to check the syntax of the Terraform files.
    -   Runs `terraform plan` to generate an execution plan. This is a dry-run that shows you what resources will be created, modified, or destroyed. **Review this output carefully.**

4.  **Helm Validation**:
    -   Navigates to the `../helm` directory.
    -   Adds and updates the required Helm repositories.
    -   Runs `helm lint` and `helm template --dry-run` for each of the charts (`kube-prometheus-stack`, `opentelemetry-collector`, `loki`, `tempo`) to check for syntax errors and render the templates locally.

If all checks pass, your environment is ready, and you can proceed with the deployment.
