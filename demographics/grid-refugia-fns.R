#' The functions here should take the demographic parameters (see README.md),
#' set up a demographic model, simulate data,
#' and compare the results to the observed data.


#' Set up the demographic model
#'
#' @param pop A population object.
#' @param pop.density Population density, in indivs/m^2
#' @param sigma Migration rate, in meters/generation.
#' @param refugia.coords Centers of refugia, in UTM coordinates (meters).
#' @param refugia.radii Common radius of refugia, in meters.
#' @param refugia.time Time refugia existed for, in generations.
#' @param expansion.time Time refugia ended and expansion began, in generations.
#' @param expansion.speed Speed of expansion, in meters per generation.
#' @param expansion.width Width of the expansion, in meters.
model_setup <- function (
                         pop,
                         pop.density,
                         sigma,
                         refugia.coords,
                         refugia.radii,
                         refugia.time,
                         contraction.speed,
                         expansion.time,
                         expansion.speed,
                         expansion.width,
                         ...
                     ) {

    ######
    # landsim pre-setup
    pop.xy <- xyFromCell(pop$habitat,cell=which(pop$accessible))
    pop.points <- SpatialPoints(pop.xy, proj4string=CRS(proj4string(pop$habitat)))

    # msarg pre-setup
    density.vec <- ( pop.density * prod(res(pop$habitat)) ) * values(pop$habitat)[pop$accessible]
    density.vec[is.na(density.vec)] <- 0

    # create the base migration matrix: WILL BE MODIFIED
    migr <- migration( kern="gaussian", sigma=sigma, 
                      radius=3*sigma, normalize=1, discretize=TRUE,
                      disc.fact=3*mean(res(pop$habitat))/sigma )
    migr.mat <- migration_matrix( pop, migration=migr )
    if (any(migr.mat<0)) { stop("negative migration rates") }
    diag(migr.mat) <- 0


    # create a population object for msarg
    pop.N <- ( pop.density * prod(res(pop$habitat)) ) * values(pop$habitat)[pop$accessible]
    pop.N[is.na(pop.N)] <- 0
    hab.grid <- new("gridArray",
                    npop = as.integer(dim(pop$habitat)[c(2,1,3)]),
                    N = pop.N,
                    G = rep( 0, sum(pop$accessible) ),
                    M = migr.mat
                )

    # create the refugia  WILL BE MODIFIED
    refugia.centers <- SpatialPoints(coords=refugia.coords,
                            proj4string=CRS(proj4string(pop$habitat)))
    refugia <- gBuffer( refugia.centers, width=refugia.radii, byid=TRUE )
    refugia.mask <- gContains( gUnaryUnion(refugia), pop.points, byid=TRUE )
    refugia.demog <- ms_demog( hab.grid )
    # endpoint of refugia
    refugia.demog <- add_to_demography( refugia.demog, tnew=expansion.time,
                                       fn=modify_grid_layer, layer=1, dN=refugia.mask )
    # beginning of refugia: before was the same as now (abruptly)
    refugia.demog <- add_to_demography( refugia.demog, tnew=expansion.time+refugia.time,
                                       pop=refugia.demog[[1]] )
    # add re-expansion to modern day (t.end=0):
    #  note due to speed may effectively end much earlier
    refugia.demog <- logistic_interpolation( refugia.demog, 
                                             t.end=0,
                                             t.begin=expansion.time, 
                                             nsteps=30, 
                                             speed=expansion.speed/mean(res(pop$habitat)), 
                                             width=expansion.width/mean(res(pop$habitat)) )
    # check this works
    if (!check_demography(refugia.demog)) { stop("Final state not communicating.") }

    return( refugia.demog )
}

#' Run ms and compute mean pairwise distances
#' @param dem A demography object, as produced by model_setup().
#' @param sample.config A sample configuration, as desired by run_ms().
#' @param outdir The output directory.
#' @param ntrees The number of trees to simulate.
sim_data <- function (
                      dem,
                      sample.config,
                      outdir,
                      ntrees
                      ) {
    # actually run ms
    run_ms( dem, nsamp=sample.config, trees=TRUE, outdir=outdir, nreps=ntrees, N.eps=0.1 )

    # parse ms output
    tree.output <- trees_from_ms( file.path(outdir,"msoutput.txt") )
    tree.dists <- tree_dists( tree.output, sample.config=sample.config )
    mean.dist <- tree.dists[[1]]
    for (k in seq_along(tree.dists)[-1]) { mean.dist <- mean.dist+tree.dists[[k]] }
    mean.dist <- mean.dist/length(tree.dists)

    return( mean.dist )
}


run_sim <- function( params, 
                    iter.num, 
                    ntrees, 
                    pop,
                    dist.df,
                    new.seed=as.integer(runif(1)*2e9), 
                    do.plots=TRUE, 
                    max.tries=5
                ) {
    outdir <- file.path(basedir, sprintf("iter_%06d",iter.num) )
    dir.create( outdir )
    cat(" ... working on", outdir, "\n")

    # (set and) save out the random seed for reproducibility/debugging
    set.seed(new.seed)
    cat( toJSON(c(params,list(seed=new.seed)), pretty=TRUE), file=file.path(outdir,"params.json") )

    ntries <- 0
    while (ntries < max.tries) {
        worked <- tryCatch( {
                    dem <- do.call( model_setup, c( list(pop=pop), params ) );
                    # takes 2-4 minutes (and note may have less than 'ntrees' trees due to segfaults)
                    mean.dist <- sim_data( dem, sample.config, outdir, ntrees );
                    TRUE
                },
                error=function (e) { 
                   cat("Whoops: restarting iteration", iter.num, ":\n"); 
                   cat("  ", e$message,"\n"); FALSE
                }
            )
        if (worked) { break }  # skip this one
        ntries <- ntries+1
    }
    if (ntries==max.tries) { stop("Failed too many times, stopping.") }

    rownames(mean.dist) <- colnames(mean.dist) <- sample.ids[sample.order]
    mean.dist <- mean.dist[msord,msord]

    # in the same order as dist.df:
    sim.dist <- mean.dist[ cbind(
                    match(dist.df[,1],sample.ids),
                    match(dist.df[,2],sample.ids) ) ]

    write( sim.dist, file=file.path(outdir,"sim-distances.csv"), ncolumns=1 )

    # mean-square difference:
    nonself <- ( dist.df$etort1 != dist.df$etort2 )
    model.score <- mean( (dist.df$generations[nonself] - sim.dist[nonself])^2 )

    write( model.score, file=file.path(outdir,"model.score") )

    # do the plots
    if (do.plots) {

        tree.output <- trees_from_ms( file.path(outdir,"msoutput.txt") )

        # pdf(file=file.path(outdir,"trees-and-things.pdf"),width=10,height=5,pointsize=10)
        png(file=file.path(outdir, "trees-and-things-%02d.png"), 
            width=10*144, height=5*144, pointsize=10, res=144)
        plot_everything( params, dist.df, sim.dist, model.score, tree.output, label=outdir )

        dev.off()
    }


    return(model.score)
}

plot_everything <- function ( params, dist.df, sim.dist, model.score, tree.output, plot.ntrees=4, label="" ) {
    full.habitat <- raster("../visualization/nussear_masked.grd")
    habitat <- aggregate( full.habitat, fact=params$hab.fact )

    # These are the two pairs of twins/repeated samples:
    #   etort-143 etort-297
    #   etort-156 etort-296
    # and there is one high-error sample:
    #   etort-50
    # We will omit these.
    omit.samples <- if (is.null(params$omit.samples)) { c("etort-296","etort-297") }  else { params$omit.samples }

    # actual sampling locations
    sample.coords <- read.csv("../tort_272_info/long-lat.csv",header=TRUE)
    sample.coords <- subset(sample.coords, ! (sample.coords$id %in% omit.samples ) )
    sample.points <- spTransform( 
            SpatialPoints( sample.coords[,1:2], 
                          proj4string=CRS("+proj=longlat +datum=WGS84 +ellps=WGS84 +towgs84=0,0,0") ), 
                 CRS(proj4string(habitat)) 
        )
    row.names(sample.points) <- sample.ids <- as.character(sample.coords$id)
    sample.cells <- cellFromXY( habitat, sample.points )
    # the "sample config" to pass to msarg: columns are row, column, layer, #.samples
    sample.config <- sort_sample_config( cbind(
                           arrayInd( unique(sample.cells), .dim=as.integer(dim(habitat)[c(2,1,3)]) ),
                           n=table(sample.cells) ) )
    # map tree tips to sample.config
    tfn <- tip_order_fn(sample.config)
    # keep track of which sample goes to which simulated sample:
    #  sample.points[k] corresponds to the sample.order[k]-th simulated indiv
    sample.rowcol <- arrayInd( sample.cells, .dim=as.integer(dim(habitat)[c(2,1,3)]) )
    sample.order <- order(sample.rowcol[, 3], sample.rowcol[, 2], sample.rowcol[, 1])
    #  and order(sample.order) is the inverse permutation
    #  so this is the permutation to re-order the ms output
    msord <- order(sample.order)

    dist.df$etort1 <- factor( as.character(dist.df$etort1), levels=sample.ids )
    dist.df$etort2 <- factor( as.character(dist.df$etort2), levels=sample.ids )

    mean.dist <- matrix( nrow=length(sample.ids), ncol=length(sample.ids) )
    rownames(mean.dist) <- colnames(mean.dist) <- sample.ids
    mean.dist[ cbind( match(dist.df$etort1,sample.ids), match(dist.df$etort2,sample.ids) ) ] <- sim.dist
    mean.dist[lower.tri(mean.dist)] <- t(mean.dist)[lower.tri(mean.dist)]

    # pcs of the covariance matrix (up to scaling; see McVean)
    covmat <- (rowMeans(mean.dist) + colMeans(mean.dist) - mean(mean.dist) - mean.dist)
    pmat <- diag(nrow(covmat)) - 1/nrow(covmat)
    pcs <- eigen( (pmat %*% covmat %*% t(pmat)) )$vectors[,1:2]
    pc.pal <- rainbow(n=32, start=4/6, end=0)
    pc.cols <- apply(pcs, 2, function (x) { pc.pal[cut(x,length(pc.pal))] } )

    # refugia centers
    refugia.centers <- SpatialPoints(coords=params$refugia.coords,
                            proj4string=CRS(proj4string(habitat)))
    refugia <- gBuffer( refugia.centers, width=params$refugia.radii, byid=TRUE )

    # for plotting nonselfs
    nonself <- ( dist.df$etort1 != dist.df$etort2 )

    layout(t(1:2))
    plot( dist.df$distance[nonself]/1e3, sim.dist[nonself], pch=20, cex=0.5, 
         xlab="geog dist (km)", ylab="mean TMRCA (gens)",
         col=adjustcolor(dist.df$col[nonself],0.5),
         main="simulated vs distance" )
    mtext(label, side=3, adj=0)
    plot( dist.df$generations[nonself], sim.dist[nonself], pch=20, cex=0.5, 
         xlim=range(dist.df$generations[nonself]),
         xlab="observed divergence", ylab="mean TMRCA (gens)",
         col=adjustcolor(dist.df$col[nonself],0.5),
         main="simulated vs observed" )
    abline(0,1)
    mtext(model.score, side=3, adj=1)

    # comparisons to individual tortoises
    layout(t(1:3))
    for (tort in paste0("etort-",c(243,35,100,262,218,52,274,90,36))) {
        ut <- with(dist.df,(etort1==tort|etort2==tort) & (etort1!=etort2))
        other <- ifelse( dist.df$etort1[ut]==tort, as.numeric(dist.df$etort2)[ut], as.numeric(dist.df$etort1)[ut] )
        plot( habitat, main=tort )
        mtext(label, side=3, adj=0, line=-1)
        plot( refugia, col=adjustcolor('black',0.25), add=TRUE )
        points( sample.points, pch=ifelse(sample.ids==tort,8,20), cex=2, col=pc.cols[,1] )
        plot( dist.df$distance[nonself]/1e3, dist.df$generations[nonself], pch=20, cex=0.5, 
             xlab="geog dist (km)", ylab="mean TMRCA (gens)", main="observed" )
        points( dist.df$distance[ut]/1e3, dist.df$generations[ut], pch=20, cex=2,
             col=pc.cols[other,1] )
        plot( dist.df$distance[nonself]/1e3, sim.dist[nonself], pch=20, cex=0.5,
             xlab="geog dist (km)", ylab="mean TMRCA (gens)", main="simulated" )
        points( dist.df$distance[ut]/1e3, sim.dist[ut], pch=20, cex=2,
             col=pc.cols[other,1] )
        mtext(model.score, side=3, adj=1)
    }

    layout(t(1:2))
    for (k in 1:ncol(pcs)) {
        plot( habitat, main=sprintf("PC %d",k) )
        if (k==1) mtext(label, side=3, adj=0, line=-1)
        if (k==ncol(pcs)) mtext(model.score, side=3, adj=1)
        plot( refugia, col=adjustcolor('black',0.25), add=TRUE )
        points( sample.points, pch=20, cex=2, col=pc.cols[,k] )
        # if (interactive() && is.null(locator(1))) { break }
    }

    for (tree in tree.output[1:plot.ntrees]) {
        plot( habitat, )
        mtext(label, side=3, adj=0, line=-1)
        mtext(model.score, side=3, adj=1, line=-1)
        plot( refugia, col=adjustcolor('black',0.25), add=TRUE )
        points( sample.points, pch=20, cex=2, col=pc.cols[,1] )
        # plot_sample_config( dem, sample.config, add=TRUE, xy=pop.xy, col=north.cols )
        pp <- plot.phylo( tree, show.tip.label=FALSE )  # tip.color=pc.cols[,k] )  # tip.color=north.cols, cex=0.2 )
        axisPhylo(1)
        ab <- abline_phylo(v=c(params$expansion.time,params$expansion.time+params$refugia.time), lty=2, col='grey')
        points( rep(1.05*ab[1],nrow(pcs)), 1:nrow(pcs), pch=20, col=pc.cols[,1][sample.order][order(tfn(tree))] )
        # if (interactive() && is.null(locator(1))) { break }
    }

}

#' Return the list x augmented by things in y that aren't in x.
merge_params <- function (x,y) {
    for (k in setdiff(names(y),names(x))) {
        if (is.null(x[[k]])) { x[[k]] <- y[[k]] }
    }
    return(x)
}
