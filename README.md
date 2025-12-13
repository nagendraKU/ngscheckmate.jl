## ngscheckmate.jl

### Julia implementation of NGSCheckMate tool - https://github.com/parklab/NGSCheckMate

_Takes a list of vcf files as input and outputs a correlation matrix of samples._

### Steps
First, generate VCF from BAM files as follows. I use nf-core/rnaseq pipeline for RNA-seq processing, and the BAM files are available in the `star_salmon` output folder.

**Notes:**
- You will need bcftools/1.22 and GNU Parallel (optional) to generate the VCF calls.
- Use the genome fasta used for the RNA-seq reference building.
- Do NOT forget to use the BED file as input for bcftools mpileup, as otherwise it will do variant calling for all SNPs observed rather than the ones that are required for ncm.jl (~20,000 SNPs). The time difference is a few seconds per file when using the BED versus several minutes without.
- Set the `-j 20` flag in the `GNU Parallel` to the number of processors available to you.

### Generate the VCF
```
find /project1/nfcore_rnaseq/r322/star_salmon -name "*.bam" | parallel -j 20 'bcftools mpileup -Ou -f Homo_sapiens.GRCh38.dna.primary_assembly.fa -R NCM_SNP_GRCh38_hg38.bed {} |  bcftools call -mv -Ou | bcftools view -O z -o /project1/vcf_calls/{/.}.vcf'

```

### Run ncm.jl to get the correlations between samples.
Then create a `vcf_list.txt` file that lists the VCF files with paths in a single column. Run the following command at the terminal.
```
export JULIA_NUM_THREADS=auto && julia ncm.jl --vcf-list project1_vcf_list.txt --bed NCM_SNP_GRCh38_hg38.bed --outdir ./project1_ncm --out-prefix project1
```

TO DO

- Create Dockerfile for Julia execution.
- Add R heatmap convenience script.
