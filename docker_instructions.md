# Docker Instructions for NGSCheckMate.jl

This document provides comprehensive instructions for running `ncm.jl` within a Docker container.

## Prerequisites

- Docker installed on your system (version 20.10 or later recommended)
- Docker Compose installed (version 1.29 or later recommended)
- Basic familiarity with command-line operations

## Quick Start

### 1. Build the Docker Image

From the repository root directory, build the Docker image:

```bash
docker-compose build
```

Alternatively, you can build using Docker directly:

```bash
docker build -t ngscheckmate-jl:latest .
```

**Note:** The Dockerfile will attempt to install Julia packages during the build process. In restricted network environments, package installation will be deferred to the container's first run. If packages are installed during build, the first run will be faster. Otherwise, the first run will take a few additional minutes to install and compile packages.

### 2. Prepare Your Data

Create a local directory to hold your input files and receive output:

```bash
mkdir -p ./data
```

Place your VCF files in this directory and create a `vcf_list.txt` file listing all VCF files (one per line with full paths relative to `/data` in the container).

Example `vcf_list.txt`:
```
/data/sample1.vcf
/data/sample2.vcf
/data/sample3.vcf
```

## Running ncm.jl in the Container

### Method 1: Using Docker Compose (Recommended)

**Display Help:**
```bash
docker-compose run --rm ngscheckmate
```

**Run Analysis:**
```bash
docker-compose run --rm ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/vcf_list.txt \
  --bed /app/ngscheckmate.jl/NCM_SNP_GRCh38_hg38.bed \
  --outdir /data/output \
  --out-prefix myproject
```

**With Optional Flags:**
```bash
docker-compose run --rm ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/vcf_list.txt \
  --bed /app/ngscheckmate.jl/NCM_SNP_GRCh38_hg38.bed \
  --outdir /data/output \
  --out-prefix myproject \
  --family-cutoff \
  --nonzero
```

**Interactive Shell Access:**
```bash
docker-compose run --rm ngscheckmate bash
```

Once inside the container, you can run Julia commands directly:
```bash
julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl --help
```

### Method 2: Using Docker Directly

**Display Help:**
```bash
docker run --rm -v $(pwd)/data:/data ngscheckmate-jl:latest
```

**Run Analysis:**
```bash
docker run --rm -v $(pwd)/data:/data ngscheckmate-jl:latest \
  julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/vcf_list.txt \
  --bed /app/ngscheckmate.jl/NCM_SNP_GRCh38_hg38.bed \
  --outdir /data/output \
  --out-prefix myproject
```

**Interactive Shell:**
```bash
docker run --rm -it -v $(pwd)/data:/data ngscheckmate-jl:latest bash
```

## Volume Mounting

### Default Configuration

By default, the `docker-compose.yml` mounts `./data` from your current directory to `/data` in the container.

### Custom Volume Mounting

To mount a different directory, you can:

**Option 1: Edit docker-compose.yml**

Modify the volumes section:
```yaml
volumes:
  - /path/to/your/local/directory:/data
```

**Option 2: Override at Runtime**

```bash
docker run --rm -v /path/to/your/data:/data ngscheckmate-jl:latest \
  julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl --vcf-list /data/vcf_list.txt ...
```

## Command-Line Arguments

The `ncm.jl` script accepts the following arguments:

| Argument | Required | Description | Default |
|----------|----------|-------------|---------|
| `--vcf-list` | Yes | Path to text file with VCF paths (one per line) | - |
| `--bed` | Yes | BED file path (NCM_SNP_GRCh38_hg38.bed is included in the image at `/app/ngscheckmate.jl/`) | - |
| `--outdir` | No | Output directory | `.` |
| `--out-prefix` | No | Output file prefix | `output` |
| `--family-cutoff` | No | Apply stricter family cutoff thresholds | `false` |
| `--nonzero` | No | Use non-zero mean depth for depth estimation | `false` |

## Output Files

The script generates the following output files in the specified output directory:

1. **`{prefix}_output_corr_matrix.txt`** - Correlation matrix of all samples
2. **`{prefix}_all.txt`** - All pairwise comparisons with correlation values
3. **`{prefix}_matched.txt`** - Only matched pairs
4. **`{prefix}.pdf`** - Hierarchical clustering dendrogram

## Environment Variables

### JULIA_NUM_THREADS

Control the number of threads Julia uses for parallel processing:

```bash
docker-compose run --rm -e JULIA_NUM_THREADS=8 ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl ...
```

Or modify `docker-compose.yml`:
```yaml
environment:
  - JULIA_NUM_THREADS=8
```

## Example Workflow

Here's a complete example workflow:

```bash
# 1. Create data directory
mkdir -p ./data/output

# 2. Copy your VCF files to ./data/
cp /path/to/your/vcf/*.vcf ./data/

# 3. Create VCF list file
# Generate vcf_list.txt with container paths
ls -1 ./data/*.vcf | sed 's|^\./data|/data|' > ./data/vcf_list.txt

# 4. Build the Docker image
docker-compose build

# 5. Run the analysis
docker-compose run --rm ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/vcf_list.txt \
  --bed /app/ngscheckmate.jl/NCM_SNP_GRCh38_hg38.bed \
  --outdir /data/output \
  --out-prefix my_analysis

# 6. View results
ls -l ./data/output/
```

## Troubleshooting

### Permission Issues

If you encounter permission issues with output files:

```bash
# Run container as current user
docker run --rm -u $(id -u):$(id -g) -v $(pwd)/data:/data ngscheckmate-jl:latest ...
```

Or add to `docker-compose.yml`:
```yaml
user: "${UID}:${GID}"
```

### Memory Issues

For large datasets, you may need to increase Docker's memory allocation:

- **Docker Desktop**: Settings → Resources → Memory
- **Linux**: Modify Docker daemon configuration

### Checking Container Status

```bash
# List running containers
docker ps

# View container logs
docker-compose logs

# Check image details
docker images | grep ngscheckmate
```

### Updating the Image

To rebuild with the latest code:

```bash
docker-compose build --no-cache
```

## Advanced Usage

### Using a Custom BED File

If you want to use a different BED file:

```bash
docker-compose run --rm ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/vcf_list.txt \
  --bed /data/my_custom.bed \
  --outdir /data/output \
  --out-prefix custom_analysis
```

### Running Multiple Analyses

You can run multiple analyses in parallel by starting separate containers:

```bash
# Terminal 1
docker-compose run --rm ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/project1_list.txt --bed /app/ngscheckmate.jl/NCM_SNP_GRCh38_hg38.bed \
  --outdir /data/project1 --out-prefix project1

# Terminal 2
docker-compose run --rm ngscheckmate julia --project=/app/ngscheckmate.jl /app/ngscheckmate.jl/ncm.jl \
  --vcf-list /data/project2_list.txt --bed /app/ngscheckmate.jl/NCM_SNP_GRCh38_hg38.bed \
  --outdir /data/project2 --out-prefix project2
```

## Cleaning Up

### Remove Containers

```bash
docker-compose down
```

### Remove Images

```bash
docker rmi ngscheckmate-jl:latest
```

### Remove All Unused Docker Resources

```bash
docker system prune -a
```

## Support

For issues or questions:
- Check the main README.md in the repository
- Review the original NGSCheckMate documentation: https://github.com/parklab/NGSCheckMate
- Open an issue on the GitHub repository

## Notes

- The BED file `NCM_SNP_GRCh38_hg38.bed` is included in the Docker image at `/app/ngscheckmate.jl/`
- All Julia packages are pre-installed during image build
- The container uses the `julia:latest` base image, which is regularly updated
- Multi-threading is enabled by default with `JULIA_NUM_THREADS=auto`
