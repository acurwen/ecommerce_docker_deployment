# Pull the node:14 base image
FROM node:14

# Set working directory
WORKDIR /app

# Pull in repo files
# RUN git clone https://github.com/acurwen/ecommerce_docker_deployment.git

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
