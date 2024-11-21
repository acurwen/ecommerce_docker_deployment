# Kura Labs Cohort 5- Deployment Workload 6


## Purpose:
The goal of this deployment was to set up an e-commerce application using cloud infrastructure tools to ensure scalability, fault tolerance, and high availability. The infrastructure was provisioned using Terraform to create and manage AWS resources and the application itself was containerized using Docker, with separate containers for the frontend and backend services. To enhance reliability, the deployment also spanned two availability zones, ensuring high availability.

## Instructions:

1. Create a t3.micro EC2 called "Jenkins" to represent your Jenkins Manager instance. Create and save new key pair.
   
For this instance:

- install Jenkins (can use a script)
- install Java 17: `sudo apt install openjdk-17-jdk`

Security Group Ports:
22 for SSH, 8080 for Jenkins

2. Create a t3.medium EC2 called "Docker_Terraform" to represent your Jenkins Node instance. Use the same key pair as Jenkins EC2.
   
For this instance, install:
- Java 17:
```
sudo apt update && sudo apt install fontconfig openjdk-17-jre software-properties-common
sudo apt install openjdk-17-jdk
```
- Terraform: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
- VSCode (Optional for editing files): https://github.com/kura-labs-org/install-sh/blob/main/vscode_install.sh
- Docker https://docs.docker.com/engine/install/ubuntu/ and [https://docs.docker.com/engine/install/linux-postinstall/](url)

- AWS CLI:
```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip
unzip awscliv2.zip
sudo ./aws/install
aws --version 
```
Create new access key and secret access key on the IAM page in AWS. After installing AWS CLI, run `aws configure` and enter your access key, secret access key, region ("us-east-1"), and output format to be "json".

Security Group Ports:
22 for SSH, 80, 8081


NOTE: Make sure you configure AWS CLI and that Terraform can create infrastructure using your credentials (Optional: Consider adding a verification in your pipeline stage to check for this to avoid errors).

Next, set up a Jenkins Node Agent in the Jenkins UI Console and check the logs to ensure the agent is "connected and online".
The Jenkins Manager serves as the director of the CICD pipeline and the Jenkins Node handles various jobs. We use the Jenkins Node to ensure the concept of least privilege, meaning that team members in charge of that specific part of the pipeline would only have access to this Node in a real-life environment. In addition using a Node agent helps with resource contention instead of having the main Jenkins Manager handle the pipeline. 

## Terraform (IaC)
Within your new Terraform directory, create your files: main.tf, variables.tf and terraform.auto.vars. Afterwards, put your terraform files into your GitHub repo in the "Terraform" directory.

Tips to keep in Mind:
- Ensure your subnets don't have coinciding CIDR blocks
- Ensure access and secret key match your IAM user
- Create and save the .pem keys created for your EC2s
- Create the following resource blocks required for the infrastructure below:

Create terraform files that will create the following infrastructure:
```
- 1x Custom VPC named "wl6vpc" in us-east-1
- VPC Peering Connection (Between Custom VPC & Default VPC)
- 2x Availability zones in us-east-1a and us-east-1b
- A Private and Public Subnet in Availability Zone: us-east-1a
- A Private and Public Subnet in Availability Zone: us-east-1b
- Internet Gateway
- Public Route Table w/ Internet Gateway (can be used for both public subnets)
- Public Route Table Association with both Public Subnets
- 2 NAT Gateways
- 2 Elastic IPs for each NAT Gateway
- Private Route Table
- Private Route Table #1 w/ NAT Gateway
- Private Route Table Association with Private Subnet #1
- Private Route Table #2 w/ NAT Gateway
- Private Route Table Association with Private Subnet #2
- 4 EC2s to be placed in each subnet (EC2s in the public subnets are for the bastion host, the EC2s in the private subnets are for the front AND backend containers of the application) Name the EC2's: "ecommerce_bastion_az1", "ecommerce_app_az1", "ecommerce_bastion_az2", "ecommerce_app_az2"
- Security Groups for each EC2 (Frontend SG Ports should be 22, 3000 and Backend SG Ports should be 22, 8000 & 9100)
- Load Balancer that will direct the inbound traffic to either of the public subnets.
- Target Group for Load Balancer: Define a target group to register your frontend instances, where the load balancer will forward traffic.
- Target Group Attachments
- Load Balancer Listener
- Security Group for Load Balancer 
- Health Checks for Load Balancer: Define these to ensure that traffic only routes to healthy frontend instances
- An RDS database
- RDS Subnet Group: Required by RDS, which specifies which subnets the database instance can run in (typically private subnets)
- Security Group for RDS
```

Use the following "user_data" code for your EC2 resource block:
```
user_data = base64encode(templatefile("${path.module}/deploy.sh", {
    rds_endpoint = aws_db_instance.main.endpoint,
    docker_user = var.dockerhub_username,
    docker_pass = var.dockerhub_password,
    docker_compose = templatefile("${path.module}/compose.yaml", {
      rds_endpoint = aws_db_instance.main.endpoint
    })
  }))
```
Also make sure that you also include the following for the EC2 resource block:
```
  depends_on = [
    aws_db_instance.main,
    aws_nat_gateway.main
  ]
```


Make sure that you declare the required variables and place the deploy.sh (create next below) and compose.yaml (provided) in the same directory as your main.tf (Terraform directory in GitHub).

## Docker: 

Next, create a deploy.sh file that will run in the "user_data" sections of the EC2 provider block:
  
  a. This script must (in this order):
  
  i. install docker and docker-compose;

  ii. log into DockerHub;

  iii. create the docker-compose.yaml with the following code:

      ```
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating app directory..."
    mkdir -p /app
    cd /app
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created and moved to /app"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating docker-compose.yml..."
    cat > docker-compose.yml <<EOF
    ${docker_compose}
    EOF
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] docker-compose.yml created"
    
---------------------------------------------------------------------

   iv. run `docker-compose pull`

   v. run `docker-compose up -d --force-recreate`

   vi. Clean the server by running a docker system prune and logging out of dockerhub.  

   vii. This script should also install Node Exporter so that you can set up your monitoring instance afterwards. https://github.com/mmajor124/monitorpractice_promgraf/blob/main/nodex.sh


Next, create Dockerfiles for the backend and frontend images and save these to your GitHub repository. 

*Dockerfile.frontend*
```
# Pull the node:14 base image
FROM node:14

# Set working directory
WORKDIR /app

# Pull in repo files
RUN git clone https://github.com/acurwen/ecommerce_docker_deployment.git

# Copy the "frontend" directory into the image
COPY frontend /app/

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
RUN sudo apt install -y nodejs

# Install the dependencies
RUN npm i

# Set Node.js options for legacy compatibility
RUN export NODE_OPTIONS=--openssl-legacy-provider

# Expose port 3000
EXPOSE 3000

# Set the command npm start to run when the container is started
ENTRYPOINT ["npm", "start"]
```

*Dockerfile.backend*
```
# Pull the python:3.9 base image
FROM python:3.9

# Set working directory
WORKDIR /app

# Pull in repo files
RUN git clone https://github.com/acurwen/ecommerce_docker_deployment.git

# Copy the "backend" directory into the image
COPY backend /app/

# Install django-environ and all other dependencies
RUN pip install -r requirements.txt

RUN pip install django-environ

# Modify "settings.py" in the "my_project" directory and update "ALLOWED_HOSTS" to include the private IP of the backend EC2. #don't need this workload

# Run python manage.py makemigrations account, python manage.py makemigrations payments, python manage.py makemigrations product
RUN python manage.py makemigrations account
RUN python manage.py makemigrations payments
RUN python manage.py makemigrations product

# Expose port 8000
EXPOSE 8000

# Set the command python manage.py runserver 0.0.0.0:8000 to run when the container is started
ENTRYPOINT ["python", "manage.py", "runserver", "0.0.0.0:8000"]

```

## CICD Pipeline:

Modify the Jenkinsfile as needed to accomodate your files.
- Build Stage should build the app environment by creating a virtual enbironment and install requirements needed for the ecommerce app.
- Test Stage is already provided to run a pytest. However, delete the lines `python backend/manage.py makemigrations` and `python backend/manage.py migrate` because in this stage in the pipeline the database won't have been created yet.
- Cleanup Stage can be left alone as is.
- Build & Push Images stage - here add in your Docker username and image name and tag in the build and push commands for both the backend and frontend.
- Lastly, the Infrastructure and post stages can be left as is. 

Modify the compose.yml file to include your image tags. Upload this file to GH.

Create a Multi-Branch pipeline called "workload_6" and run the pipeline to deploy the application! Be sure to also save credentials needed in the Jenkins Securtiy Credentials section of the Jenkins Dashboard.

Lastly, Create a monitoring EC2 in the default VPC that will monitor the resources of the various servers. 


## System Design Diagram
![image](https://github.com/user-attachments/assets/8f99b4f9-bf4a-420e-96bd-93d8fcf0bcca)

## Issues/Troubleshooting

Throughout the deployment process, I encountered several challenges that required troubleshooting and adjustments:

Offline Status for Node Instance Agent:
Initially, the Node Instance agent showed an "offline" status. This happened because I forgot to install Java 17 on the Docker_Terraform instance. Installing the required Java version resolved the issue.

Duplicate Migration Commands:
The migration commands were inadvertently configured to run on both EC2 instances in the compose.yml file. Since these commands only need to execute on a single EC2 instance, running them in duplicate caused conflicts and disrupted the migration process. Unfortunately, I was unable to determine how to restrict these commands to just one container during this project.

Unhealthy Endpoints in Load Balancer:
Upon deployment, the load balancer displayed unhealthy endpoints. The root cause was that the application containers were not fully initialized. The issue was resolved by SSHing into the application EC2 instances and verifying that all containers were running as expected.

Unable to SSH into Bastion Hosts:
SSH access to the Bastion Hosts was initially blocked due to a misconfigured security group. The source for the Bastion Host's security group was mistakenly set to the IP of the Custom VPC. Correcting this configuration to allow all sources resolved the problem.

Missing Dependencies in Terraform Configuration:
The following dependency blocks were omitted in my EC2 provider configuration, which caused provisioning issues in Terraform:
```
 depends_on = [
    aws_db_instance.main,
    aws_nat_gateway.main
  ]
```
Adding these dependencies ensured that the EC2 instances were created only after the database and NAT gateway were fully provisioned.

Redundant git clone in Dockerfiles:
Initially, I included a git clone command in my Dockerfiles to pull the project repository. However, I realized this was unnecessary because Jenkins already pulls the repository during the CI/CD pipeline. .


## Optimization
To further optimize this deployment, we could have used separate EC2 Instances for the frontend and backend. Currently, both the frontend and backend services are hosted on the same EC2 instance. This architecture introduces a single point of failure—if the EC2 instance goes down, both services are impacted. Hosting the frontend and backend on separate EC2 instances would improve fault tolerance and better align with real-world scenarios where teams often work independently on different parts of an application. This would also aid the ability to scale containers dynamically, optimize resource allocation and improve disaster recovery.

## Conclusion
This project successfully demonstrated the deployment of a fault tolerant e-commerce application using Docker, Terraform, and Jenkins across multiple availability zones. It provided valuable insights into the real-world challenges of application deployment and the practical application of modern cloud tools. By integrating these technologies, I gained a deeper understanding of infrastructure-as-code, containerization, and CI/CD pipelines, which are essential for efficient and scalable application delivery.
