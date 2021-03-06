#!/usr/bin/Rscript

usage <- "
Convert hitting times on one grid to another.  Usage:
   Rscript disaggregate-ht.R (layer prefix 1) (layer prefix 2) (subdir 1) (subdir 2) (layer file) (prev ht) (aggregation factor)
where
    (layer prefix 1) = prefix of (coarser) layers hitting times are computed on
    (layer prefix 2) = prefix of (finer) layers we are disaggreating to
    (subdir 1) = subdirectory information about coarse layers is stored in
    (subdir 2) = subdirectory disaggregated hitting times should be saved to
    (layer file) = file with names of layers to use
    (prev ht) = file with (coarse) hitting times to disaggregate
    (aggregation factor) = multiplicative factor to disaggregate by: ( resolution of layer.prefix.2 ) = ag.fact * ( resolution of layer.prefix.1 )

For example,
    Rscript disaggregate-ht.R ../geolayers/multigrid/512x/crm_ ../geolayers/multigrid/256x/crm_ 512x 256x six-raster-list 512x/six-raster-list-hitting-times.tsv 2
will move `512x/six-raster-list-hitting-times.tsv` up to 256x, a factor of 2.
"

if (length(commandArgs(TRUE)) < 7) { stop(usage) }

source("resistance-fns.R")
require(raster)
rasterOptions(tmpdir=".")


require(parallel)
numcores<-getcores()


if (!interactive()) {
    layer.prefix.1 <- commandArgs(TRUE)[1]
    layer.prefix.2 <- commandArgs(TRUE)[2]
    subdir.1 <- commandArgs(TRUE)[3]
    subdir.2 <- commandArgs(TRUE)[4]
    layer.file <- commandArgs(TRUE)[5]
    prev.ht <- commandArgs(TRUE)[6]
    ag.fact <- as.numeric( commandArgs(TRUE)[7] )
} else {
    layer.prefix.1 <- "../geolayers/TIFF/500x/500x_"
    layer.prefix.2 <- "../geolayers/TIFF/100x/crop_resampled_masked_aggregated_100x_"
    subdir.1 <- "500x"
    subdir.2 <- "100x"
    layer.file <- "six-raster-list"
    prev.ht <- "500x/six-raster-list-hitting-times.tsv"
    ag.fact <- 5
}

hts <- read.table(prev.ht,header=TRUE)

env <- new.env()
load( paste(subdir.1, "/", basename(layer.prefix.1), "_", basename(layer.file), "_nonmissing.RData",sep=''), envir=env ) # provides nonmissing
nonmissing.1 <- with( env, nonmissing )
load( paste(subdir.2, "/", basename(layer.prefix.2), "_", basename(layer.file), "_nonmissing.RData",sep=''), envir=env ) # provides nonmissing
nonmissing.2 <- with( env, nonmissing )

layer.name <- "dem_30"
layer.1 <- raster(paste(layer.prefix.1,layer.name,sep=''))
layer.2 <- raster(paste(layer.prefix.2,layer.name,sep=''))

values(layer.1)[-nonmissing.1] <- NA
values(layer.2)[-nonmissing.2] <- NA

##

# omit aggregation error check for larger grids
checkit <- ( subdir.1 == "500x" )

# do the disaggregation
new.hts <- upsample.hts( hts, ag.fact, layer.1, nonmissing.1, layer.2, nonmissing.2, checkit, numcores=numcores )

outfile <- paste( subdir.2, "/", basename(subdir.1), "-", basename(layer.file), "-aggregated-hitting-times.tsv", sep='')
write.table( new.hts, file=outfile, row.names=FALSE )
cat("Writing output to ", outfile, " .\n")

if (FALSE) {
    layout(t(1:4))
    plot(layer.1)
    plot(layer.1.dis)
    plot(layer.1.dis.res)
    plot(layer.1.dis.res-layer.1.dis)
    # plot(layer.2)
}
