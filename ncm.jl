#!/usr/bin/env julia

using ArgParse
using Statistics
using LinearAlgebra
using Printf
using GeneticVariation: VCF

# Overview: Julia reimplementation of VCF-only NGSCheckMate workflow with depth-aware correlation matching.

mutable struct SampleStore
    name::String
    scores::Vector{Float64}
    seen::Vector{Bool}
    depth_sum::Float64
    real_count::Int
end

mutable struct Config
    features::Vector{String}
    feature_to_idx::Dict{String,Int}
    family_cutoff::Bool
    nonzero::Bool
    outdir::String
    out_prefix::String
end

const PARSE_LOCK = ReentrantLock()
const MIN_SHARED = 5  # minimum number of shared loci to classify; smaller -> insufficient data

# Parse BED file to extract feature loci (chrom_position keys) and build index for O(1) lookup
function func_LoadBed(bed_path::String)
    # Manual BED parsing: columns: chrom, start, end, [other fields]. Use `end` as 1-based pos.
    features = String[]
    feature_to_idx = Dict{String,Int}()
    open(bed_path, "r") do io
        for line in eachline(io)
            l = strip(line)
            isempty(l) && continue
            startswith(l, "#") && continue
            fields = split(l, '\t')
            length(fields) < 3 && continue
            chrom = fields[1]
            pos = fields[3]
            # Normalize chrom with or without chr prefix: keep as given in bed (assume correct fmt)
            key = string(chrom, "_", pos)
            if !haskey(feature_to_idx, key)
                feature_to_idx[key] = length(features) + 1
                push!(features, key)
            end
        end
    end
    return features, feature_to_idx
end

# Initialize per-sample storage for allele fractions, observed loci flags, and depth statistics
function func_InitSample(name::String, feature_count::Int)
    scores = zeros(Float64, feature_count)
    seen = falses(feature_count)
    return SampleStore(name, scores, seen, 0.0, 0)
end

# Parse VCF records extracting alt allele fractions from DP4 (mpileup) or AD/DP (GATK) fields
# for BED-defined loci; accumulate depth and mark observed loci per sample
function func_ParseVcf(vcf_path::String, features::Vector{String}, feature_to_idx::Dict{String,Int})
    reader = VCF.Reader(open(vcf_path, "r"))
    sample_names = reader.header.sampleID
    feature_count = length(features)
    samples = [func_InitSample(name, feature_count) for name in sample_names]

    for record in reader
        chrom = string(VCF.chrom(record))
        pos = string(VCF.pos(record))
        key = startswith(chrom, "chr") ? string(chrom[4:end], "_", pos) : string(chrom, "_", pos)
        haskey(feature_to_idx, key) || continue
        idx = feature_to_idx[key]

        info_dict = Dict(VCF.info(record))
        dp4_val = haskey(info_dict, "DP4") ? info_dict["DP4"] : nothing

        if dp4_val !== nothing
            # DP4 may be a string like "a,b,c,d" (common) or a numeric vector; normalize
            dp4_vals = Float64[]
            if typeof(dp4_val) <: AbstractString
                vals = split(dp4_val, ',')
                for v in vals
                    try
                        push!(dp4_vals, parse(Float64, strip(v)))
                    catch
                        # skip parse failure
                    end
                end
            else
                for v in dp4_val
                    push!(dp4_vals, float(v))
                end
            end
            if length(dp4_vals) >= 4
                refF = dp4_vals[1]; refR = dp4_vals[2]; altF = dp4_vals[3]; altR = dp4_vals[4]
                total = refF + refR + altF + altR
                score = total > 0 ? (altF + altR) / total : 0.0
            end
            for s in samples
                s.scores[idx] = score
                s.seen[idx] = true
                s.depth_sum += total
                s.real_count += total > 0 ? 1 : 0
            end
            continue
        end

        format_keys = Vector{String}(VCF.format(record))
        ad_idx = findfirst(==("AD"), format_keys)
        dp_idx = findfirst(==("DP"), format_keys)
        ad_idx === nothing && continue
        dp_idx === nothing && continue

        gts = VCF.genotypes(record)
        for (i, gt) in enumerate(gts)
            gt_dict = Dict(gt)
            ad_val = haskey(gt_dict, "AD") ? gt_dict["AD"] : nothing
            dp_val = haskey(gt_dict, "DP") ? gt_dict["DP"] : nothing
            ad_val === nothing && continue
            dp_val === nothing && continue
            (length(ad_val) < 2) && continue
            refc = float(ad_val[1])
            altc = float(ad_val[2])
            depth = float(dp_val)
            score = (refc + altc) < 0.5 ? 0.0 : altc / (refc + altc)
            s = samples[i]
            s.scores[idx] = score
            s.seen[idx] = true
            s.depth_sum += depth
            s.real_count += depth > 0 ? 1 : 0
        end
    end
    return samples
end

# Compute Pearson correlation between two vectors using only loci where mask is true
function func_PearsonMasked(a::Vector{Float64}, b::Vector{Float64}, mask::Union{Vector{Bool},BitVector})
    n = count(identity, mask)
    n == 0 && return 0.0
    sum_a = 0.0
    sum_b = 0.0
    sum_a2 = 0.0
    sum_b2 = 0.0
    sum_ab = 0.0
    for i in eachindex(mask)
        mask[i] || continue
        av = a[i]
        bv = b[i]
        sum_a += av
        sum_b += bv
        sum_a2 += av * av
        sum_b2 += bv * bv
        sum_ab += av * bv
    end
    mean_a = sum_a / n
    mean_b = sum_b / n
    cov = sum_ab / n - mean_a * mean_b
    var_a = sum_a2 / n - mean_a^2
    var_b = sum_b2 / n - mean_b^2
    denom = sqrt(var_a * var_b)
    if denom == 0.0
        # If all values equal in the masked region and equal between arrays, treat as perfect correlation
        all_equal = true
        first_val = nothing
        for i in eachindex(mask)
            mask[i] || continue
            av = a[i]
            bv = b[i]
            if first_val === nothing
                first_val = av
            else
                if av != first_val
                    all_equal = false
                    break
                end
            end
            if av != bv
                all_equal = false
                break
            end
        end
        return all_equal ? 1.0 : 0.0
    end
    return cov / denom
end

# Retrieve depth-binned correlation thresholds (pos_mean, pos_sd, neg_mean, neg_sd)
# for matched vs unmatched classification; family=true applies stricter thresholds
function func_GetPredefinedModel(depth::Float64, family::Bool)
    if family
        return depth > 10 ? (0.874611,0.022596,0.644481,0.020908) :
               depth > 5  ? (0.785312,0.021318,0.596133,0.022502) :
               depth > 2  ? (0.650299,0.019252,0.5346,0.020694)  :
               depth > 1  ? (0.578582,0.018379,0.495017,0.021652) :
               depth > 0.5 ? (0.524757,0.023218,0.465653,0.027378) :
                             (0.524757,0.023218,0.465653,0.027378)
    else
        return depth > 10 ? (0.874546,0.022211,0.310549,0.060058) :
               depth > 5  ? (0.785249,0.021017,0.279778,0.054104) :
               depth > 2  ? (0.650573,0.018699,0.238972,0.047196) :
               depth > 1  ? (0.578386,0.018526,0.222322,0.041186) :
               depth > 0.5 ? (0.529327,0.025785,0.217839,0.040334) :
                             (0.529327,0.025785,0.217839,0.040334)
    end
end

# Classify observed correlation as matched (1) or unmatched (0) using distance from
# predefined unmatched (p0) and matched (p1) distributions with standard deviations
function func_ClassifyNV(obs::Float64, p0::Float64, p0s::Float64, p1::Float64, p1s::Float64)
    return abs(p0 - obs) - p0s > abs(p1 - obs) - p1s ? (abs((abs(p0 - obs) - p0s) / (abs(p1 - obs) - p1s)), 1) :
                                                       (abs((abs(p0 - obs) - p0s) / (abs(p1 - obs) - p1s)), 0)
end

# Compute pairwise Pearson correlations on shared loci and classify each pair as
# matched/unmatched using depth-aware thresholds; parallelized over sample pairs
function func_CorrelateAndClassify(samples::Vector{SampleStore}, cfg::Config)
    n = length(samples)
    corr_matrix = zeros(Float64, n, n)
    labels = Matrix{Int}(undef, n, n)
    Threads.@threads for idx in 1:n
        for j in idx+1:n
            s1 = samples[idx]
            s2 = samples[j]
            mask = s1.seen .& s2.seen
            n_mask = count(identity, mask)
            corr = func_PearsonMasked(s1.scores, s2.scores, mask)
            depth = cfg.nonzero ? min(s1.real_count == 0 ? 0.0 : s1.depth_sum / s1.real_count,
                                      s2.real_count == 0 ? 0.0 : s2.depth_sum / s2.real_count) :
                                   min(s1.depth_sum / length(cfg.features), s2.depth_sum / length(cfg.features))
            if n_mask < MIN_SHARED
                # Insufficient data: label as -1
                matched = -1
                score = 0.0
            else
                p1, p1s, p0, p0s = func_GetPredefinedModel(depth, cfg.family_cutoff)
                score, matched = func_ClassifyNV(corr, p0, p0s, p1, p1s)
            end
            corr_matrix[idx, j] = matched == 1 ? corr : 0.0
            corr_matrix[j, idx] = corr_matrix[idx, j]
            labels[idx, j] = matched
            labels[j, idx] = matched
        end
    end
    for i in 1:n
        corr_matrix[i, i] = 1.0
        labels[i, i] = 1
    end
    return corr_matrix, labels
end


# Write correlation matrix, all pairwise comparisons, and matched-only pairs to TSV files
function func_WriteOutputs(samples::Vector{SampleStore}, corr::Matrix{Float64}, labels::Matrix{Int}, cfg::Config)
    mkpath(cfg.outdir)
    matrix_path = joinpath(cfg.outdir, cfg.out_prefix * "_output_corr_matrix.txt")
    all_path = joinpath(cfg.outdir, cfg.out_prefix * "_all.txt")
    matched_path = joinpath(cfg.outdir, cfg.out_prefix * "_matched.txt")

    open(matrix_path, "w") do io
        print(io, "sample_ID")
        for s in samples
            print(io, '\t', s.name)
        end
        println(io)
        for (i, s) in enumerate(samples)
            print(io, s.name)
            for j in 1:length(samples)
                print(io, '\t', @sprintf("%.4f", corr[i, j]))
            end
            println(io)
        end
    end

    open(all_path, "w") do io_all
        open(matched_path, "w") do io_match
            # Write headers for _all.txt and _matched.txt for clarity
            header = string("sample_A", '\t', "label", '\t', "sample_B", '\t', "correlation", '\t', "depth", '\t', "shared_count")
            println(io_all, header)
            println(io_match, header)
            for i in 1:length(samples)-1
                for j in i+1:length(samples)
                            if labels[i, j] == 1
                                label = "matched"
                            elseif labels[i, j] == -1
                                label = "insufficient"
                            else
                                label = "unmatched"
                            end
                          depth = cfg.nonzero ? min(samples[i].real_count == 0 ? 0.0 : samples[i].depth_sum / samples[i].real_count,
                                                             samples[j].real_count == 0 ? 0.0 : samples[j].depth_sum / samples[j].real_count) :
                                                         min(samples[i].depth_sum / length(cfg.features), samples[j].depth_sum / length(cfg.features))
                          shared_count = count(identity, samples[i].seen .& samples[j].seen)
                          line = string(samples[i].name, '\t', label, '\t', samples[j].name, '\t', @sprintf("%.4f", corr[i, j]), '\t', @sprintf("%.2f", depth), '\t', string(shared_count))
                          # output is sample name, match status, compared sample name, correlation, depth, shared SNPs
                    println(io_all, line)
                    labels[i, j] == 1 && println(io_match, line)
                end
            end
        end
    end
end

 

# --- Argument parsing functions ---
# Define and parse command-line arguments for VCF list, BED file, output options, and flags
function func_ParseArgs()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--vcf-list"
            help = "Path to text file with absolute VCF paths (one per line)"
            arg_type = String
            required = true
        "--bed"
            help = "BED file without chr prefix"
            arg_type = String
            required = true
        "--outdir"
            help = "Output directory"
            arg_type = String
            default = "."
        "--out-prefix"
            help = "Output prefix"
            arg_type = String
            default = "output"
        "--family-cutoff"
            help = "Apply stricter family cutoff thresholds"
            action = :store_true
        "--nonzero"
            help = "Use non-zero mean depth for depth estimation"
            action = :store_true
    end
    return parse_args(s)
end

# Retrieve CLI argument supporting both underscore and dash formats (e.g., vcf_list or vcf-list)
function func_GetArg(args::Dict{String,Any}, key::String)
    haskey(args, key) && return args[key]
    dash = replace(key, "_" => "-")
    haskey(args, dash) && return args[dash]
    error("Missing required argument: " * key)
end


# Load VCF file paths from single-column text file, skipping empty lines
function func_LoadVcfList(list_path::String)
    v = String[]
    open(list_path, "r") do io
        for line in eachline(io)
            stripped = strip(line)
            isempty(stripped) && continue
            push!(v, stripped)
        end
    end
    isempty(v) && error("VCF list is empty")
    return v
end


# Orchestrate workflow: parse args, load BED features, parse VCFs in parallel,
# compute correlations, classify pairs, write outputs, and plot dendrogram
function func_Main()
    args = func_ParseArgs()
    vcf_list = func_LoadVcfList(func_GetArg(args, "vcf_list"))
    bed_path = func_GetArg(args, "bed")
    outdir = get(args, "outdir", get(args, "out-dir", "."))
    out_prefix = get(args, "out_prefix", get(args, "out-prefix", "output"))
    features, feature_to_idx = func_LoadBed(bed_path)
    cfg = Config(features, feature_to_idx, get(args, "family_cutoff", get(args, "family-cutoff", false)), get(args, "nonzero", get(args, "non-zero", false)), outdir, out_prefix)

    sample_accum = SampleStore[]
    Threads.@threads for path in vcf_list
        samples = func_ParseVcf(path, cfg.features, cfg.feature_to_idx)
        lock(PARSE_LOCK) do
            append!(sample_accum, samples)
        end
    end

    corr, labels = func_CorrelateAndClassify(sample_accum, cfg)
    func_WriteOutputs(sample_accum, corr, labels, cfg)
end

if abspath(PROGRAM_FILE) == @__FILE__
    func_Main()
end

# Contains AI-generated edits.
