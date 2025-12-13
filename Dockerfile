# Use the official Julia image (latest version)
FROM julia:latest

# Set the working directory inside the container
WORKDIR /app

# Install system dependencies if needed (for graphics/plotting)
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone the repository
RUN git clone https://github.com/nagendraKU/ngscheckmate.jl.git /app/ngscheckmate.jl

# Set the working directory to the cloned repo
WORKDIR /app/ngscheckmate.jl

# Copy the Project.toml to ensure dependencies are installed
# (This is redundant if already in the repo but ensures it's available)
COPY Project.toml /app/ngscheckmate.jl/Project.toml

# Instantiate the Julia environment to install all required packages
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# Make ncm.jl executable
RUN chmod +x ncm.jl

# Set environment variable for Julia threads (can be overridden at runtime)
ENV JULIA_NUM_THREADS=auto

# Create a directory for user data/output
RUN mkdir -p /data

# Set the working directory to /data for user files
WORKDIR /data

# Default command - show help
CMD ["julia", "--project=/app/ngscheckmate.jl", "/app/ngscheckmate.jl/ncm.jl", "--help"]
