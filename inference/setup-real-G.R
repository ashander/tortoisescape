#!/usr/bin/Rscript

usage <- "
Setup the generator matrix and information to translate from nonmissing index back to raster index.  Usage:
    Rscript setup-real-G.R (layer prefix) (subdir) (layer file)
e.g.
    Rscript setup-real-G.R ../geolayers/multigrid/512x/crm_ 512x six-raster-list
where
    (layer prefix) = prefix to look for raster files in
    (layer file) = file with names of layers to use

Creates two files, one with G and associated information and one with nonmissing locations:
    (subdir)/(file part of prefix)_six-raster-list_G.RData
    (subdir)/(file part of prefix)_six-raster-list_nonmissing.RData
"

if (length(commandArgs(TRUE))<3) { stop(usage) }

if (!interactive()) { 
    layer.prefix <- commandArgs(TRUE)[1] 
    subdir <- commandArgs(TRUE)[2]
    layer.file <- commandArgs(TRUE)[3]
} else {
    layer.prefix <- c("../geolayers/TIFF/500x/500x_")
    subdir <- "500x"
    layer.file <- "six-raster-list"
}

source("resistance-fns.R")
require(raster)
rasterOptions(tmpdir=".")

# for (layer.prefix in c( "../geolayers/TIFF/100x/crop_resampled_masked_aggregated_100x_", "../geolayers/TIFF/10x/crop_resampled_masked_aggregated_10x_", "../geolayers/TIFF/masked/crop_resampled_masked_" ) ) {

    # # minimal list to make sure this works with update.G below
    # layer.names <- c("annual_precip","lon_gcs_30")
    na.layer.name <- paste( basename(layer.file), "-na", sep='' )  # this is TRUE in cells with missing data

    layer.names <- scan(layer.file,what='char')

    init.params <- c( beta=0.0, gamma=rep(.01,length(layer.names)), delta=rep(.01,length(layer.names)) )

    ###
    # layer whatnot

    # get info out of na layer
    nalayer <- raster(paste(dirname(layer.prefix),"/",na.layer.name,sep=''))
    nonmissing <- which(values(nalayer)==0)

    ###
    # generator matrix
    G <- make.G( layer=nalayer, nonmissing=nonmissing )
    Gjj <- p.to.j(G@p)

    layers <- sapply( layer.names, function (ln) {
                scale( values( raster( paste(layer.prefix,ln,sep='') ) )[nonmissing] )
            } )
    stopifnot(nrow(layers)==nrow(G))
    
    # ADD the constant layer
    layers <- cbind( 1, layers )
    layer.names <- c( "constant", layer.names )

    # transfn <- exp
    transfn <- function (x) { 1/(1+exp(-x)) }
    # valfn <- function (gamma) { ( rowSums( layers * gamma[col(layers)], na.rm=TRUE ) ) }
    # this is faster if we don't have to worry about NAs (we shouldn't?)
    valfn <- function (gamma) { ans <- layers[,1]*gamma[1]; for (k in (1:NCOL(layers))[-1]) { ans <- ans+layers[,k]*gamma[k] }; return(ans) }

    ndelta <- ngamma <- length(layer.names)
    update.G <- function(params) {
        stopifnot(length(params)==2+2*ncol(layers))
        beta <- params[1]
        gamma <- params[1+(1:ngamma)]
        delta <- params[1+ngamma+(1:ndelta)]
        return( exp(beta) * transfn(valfn(gamma))[G@i+1L] * transfn( valfn(delta)[G@i+1L] + valfn(delta)[Gjj] ) )
    }

    G@x <- update.G(init.params)

	dir.create(subdir,showWarnings=FALSE,recursive=TRUE)
    G.outfile <- paste(subdir,"/",basename(layer.prefix),"_",basename(layer.file),"_","G.RData",sep='')
    save( G, Gjj, update.G, ndelta, ngamma, transfn, valfn, layers, file=G.outfile )
    cat("Saved to G, updating info to ", G.outfile, " .\n")
    nonmissing.outfile <- paste(subdir,"/",basename(layer.prefix),"_",basename(layer.file),"_","nonmissing.RData",sep='')
    save( nonmissing, file=nonmissing.outfile)
    cat("Saved nonmissing info to ", nonmissing.outfile, " .\n")
    # }
