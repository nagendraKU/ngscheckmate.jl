#!/bin/bash
set -e

# Check if packages are installed by looking for the Manifest.toml
if [ ! -f "/app/ngscheckmate.jl/Manifest.toml" ]; then
    echo "================================================"
    echo "First run detected. Installing Julia packages..."
    echo "This may take a few minutes..."
    echo "================================================"
    cd /app/ngscheckmate.jl
    julia --project=. -e 'using Pkg; Pkg.instantiate()'
    echo "================================================"
    echo "Julia packages installed successfully!"
    echo "================================================"
fi

# Execute the command passed to docker run
exec "$@"
