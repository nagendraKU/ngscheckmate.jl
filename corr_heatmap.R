#!/usr/bin/env Rscript
# Heatmap plotting helper
# Reads a correlation matrix file, sorts rows/columns in ascending order,
# creates a pheatmap, converts to a ggplot object using ggplotify, and
# saves the plot using ggsave.

library(pheatmap)
library(ggplot2)
library(ggplotify)
library(RColorBrewer)

#' Create a heatmap from a correlation matrix file and save as pdf
#'
#' @param InFile Path to the correlation matrix text file (tab/whitespace delimited).
#'               First column should contain row names, and the file should contain a header.
#' @param OutFile Path to output image file (png, pdf, svg, etc.)
#' @param Width Width in inches for ggsave
#' @param Height Height in inches for ggsave
#' @return invisibly returns the ggplot object created from the pheatmap

func_CreateCorrelationHeatmap <- function(
    InFile = "corr_matrix.txt",
    OutFile = "ncm_heatmap_output.pdf",
    Width = 8,
    Height = 8
) {
    # Argument checks
    if (!file.exists(InFile)) {
        stop(sprintf("Input file '%s' not found.", InFile))
    }

    # Read matrix: assume first column holds rownames and header present
    df <- tryCatch(
        read.table(
            InFile,
            header = TRUE,
            sep = "\t",
            row.names = 1,
            check.names = FALSE,
            stringsAsFactors = FALSE
        ),
        error = function(e) {
            read.table(
                InFile,
                header = TRUE,
                sep = " ",
                row.names = 1,
                check.names = FALSE,
                stringsAsFactors = FALSE
            )
        }
    )

    # Ensure numeric matrix
    mat <- as.matrix(df)
    if (!is.numeric(mat)) {
        mat <- apply(mat, 2, function(x) as.numeric(as.character(x)))
        rownames(mat) <- rownames(df)
    }

    # Determine common labels between rows and columns
    rowLabs <- rownames(mat)
    colLabs <- colnames(mat)
    common <- intersect(rowLabs, colLabs)
    if (length(common) == 0L) {
        stop(
            "No common row/column labels found in the matrix. Ensure it is a square correlation matrix with matching row and column names."
        )
    }

    # Warn if not symmetric but continue using the intersection
    if (!all(rowLabs == colLabs)) {
        warning(
            "Row and column labels differ. Using the intersection of labels for sorting and plotting."
        )
    }

    # Sort labels in ascending order (alphabetical by label) and reindex matrix
    sortedLabs <- sort(common, decreasing = FALSE)
    matSorted <- mat[sortedLabs, sortedLabs, drop = FALSE]

    # Color palette for correlations: blue-white-red
    Colors <- colorRampPalette(c("#eff15e", "#FFFFFF", "#B2182B"))(50)

    # Use pheatmap to create the heatmap without clustering (we sorted already)
    PHeatObj <- as.ggplot(pheatmap(
        matSorted,
        color = Colors,
        cellwidth = 1,
        cellheight = 1,
        cluster_rows = FALSE,
        cluster_cols = FALSE,
        border_color = NA,
        show_rownames = TRUE,
        show_colnames = TRUE,
        fontsize = 3,
        main = "Sample Correlation heatmap",
        silent = TRUE
    ))

    # Save with ggsave
    ggplot2::ggsave(
        filename = OutFile,
        plot = PHeatObj,
        width = Width,
        height = Height
    )

    # Return the ggplot object invisibly
    invisible(PHeatObj)
}

# Generates the output
func_CreateCorrelationHeatmap(
    InFile = "lbw_muscle_output_corr_matrix.txt",
    OutFile = "heatmap_samples.pdf",
    Width = 7,
    Height = 7
)


# Contains AI-generated edits.
