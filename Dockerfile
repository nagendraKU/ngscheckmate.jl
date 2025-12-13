# Use the official Julia image (latest version)
FROM julia:latest

# Set the working directory inside the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create the application directory
RUN mkdir -p /app/ngscheckmate.jl

# Set the working directory to the app
WORKDIR /app/ngscheckmate.jl

# Copy the project files from the build context
COPY Project.toml /app/ngscheckmate.jl/
COPY ncm.jl /app/ngscheckmate.jl/
COPY NCM_SNP_GRCh38_hg38.bed /app/ngscheckmate.jl/
COPY README.md /app/ngscheckmate.jl/
COPY entrypoint.sh /entrypoint.sh

# Try to install packages during build (may fail in restricted environments)
# Packages will be installed on first container run if this step fails
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()' || echo "Package installation will occur on first container run"

# Make scripts executable
RUN chmod +x ncm.jl /entrypoint.sh

# Set environment variable for Julia threads (can be overridden at runtime)
ENV JULIA_NUM_THREADS=auto

# Create a directory for user data/output
RUN mkdir -p /data

# Set the working directory to /data for user files
WORKDIR /data

# Set entrypoint to handle package installation on first run
ENTRYPOINT ["/entrypoint.sh"]

# Default command - show help
CMD ["julia", "--project=/app/ngscheckmate.jl", "/app/ngscheckmate.jl/ncm.jl", "--help"]
