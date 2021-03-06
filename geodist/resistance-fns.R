#!/usr/bin/Rscript

# number of cores for parallel
getcores <- function (subdir) {
    if ( "parallel" %in% .packages()) {
        cpupipe <- pipe("cat /proc/cpuinfo | grep processor | tail -n 1 | awk '{print $3}'")
        numcores <- 1+as.numeric(scan(cpupipe))
        close(cpupipe)
    } else {
        numcores <- 1
    }
    if ( !missing(subdir) && ( as.numeric(gsub("x","",subdir)) < 50 ) ) {
        numcores <- 1
    }
    return(numcores)
}

# move @p to @j in dgCMatrix
p.to.j <- function (p) { rep( seq.int( length(p)-1 ), diff(p) ) }

# mappings between index in a matrix of height (in rows) n
#   ZERO-BASED: (i,j) and column-oriented (k)
#   ALLOW indices outside the grid
.ob <- function (ij,n,m){ ( ij[,1] >= 0 ) & ( ij[,1] < n ) & ( ij[,2] >= 0 ) & ( ij[,2] < m ) } # outside grid
ij.to.k <- function (ij,n,m) { if (is.null(dim(ij))) { dim(ij) <- c(1,length(ij)) }; ifelse( .ob(ij,n,m), ij[,1,drop=FALSE]+ij[,2,drop=FALSE]*n, NA ) }
k.to.ij <- function (k,n) { cbind( k%%n, k%/%n ) }
shift <- function (dij,k,n,m) { ij.to.k( sweep( k.to.ij(k,n), 2, as.integer(dij), "+" ), n, m ) }

require(Matrix)

grid.dist <- function (ij) {
    # return matrix of pairwise as-the-crow-flies distances
    sqrt( outer(ij[,1],ij[,1],"-")^2 + outer(ij[,2],ij[,2],"-")^2 )
}

grid.adjacency <- function (n,m=n,diag=TRUE,symmetric=TRUE) {
    # for a grid of height n and width m
    nn <- 0:(n*m-1)
    nreps <- if(diag){5}else{4}
    adj <- data.frame(
            i=rep(nn, nreps),
            j=c( if(diag){nn}else{NULL},
                 shift(c(+1,0),nn,n,m),
                 shift(c(-1,0),nn,n,m),
                 shift(c(0,+1),nn,n,m),
                 shift(c(0,-1),nn,n,m)
                 )
            )
    # on the boundary?
    usethese <- ! ( is.na(adj$j) | !.ob(k.to.ij(adj$j,n),n,m) | !.ob(k.to.ij(adj$i,n),n,m) )
    if (symmetric) { usethese <- ( usethese & ( adj$i <= adj$j ) ) }
    # add 1 since we worked 0-based above; sparseMatrix (unlike underlying representation) is 1-based.
    A <- with( subset(adj, usethese ), sparseMatrix( i=i+1L, j=j+1L, x=1.0, dims=c(n*m,n*m), symmetric=symmetric ) )
    return(A)
}

grid.sum <- function (n,m=n,direction,zeros=FALSE) {
    # for a grid of height n and width m,
    #   return operator that sums each site with the other one at displacement 'direction'
    # if there is no such site, either:
    # if (zeros) : include zero rows
    # else : omit these,
    #   and SHOULD RETURN IN SAME ORDER AS grid.adjacency
    nn <- 0:(n*m-1)
    nreps <- 2
    adj <- data.frame(
            i=rep(nn, nreps),
            j=c( nn,
                 shift(direction,nn,n,m)
                 ),
            x=rep(1,nreps*length(nn))
            )
    # on the boundary?
    usethese <- with( adj[n*m+(1:(n*m)),], ! ( is.na(j) | !.ob(k.to.ij(j,n),n,m) | !.ob(k.to.ij(i,n),n,m) ) )
    adj <- subset( adj, c(usethese,usethese) )
    if (!zeros) {
        # remove zero-rows
        zrows <- cumsum( tabulate( 1L+adj$i, nbins=n*m ) > 0 )
        adj$i <- zrows[ 1L+adj$i ] - 1L
    }
    # add 1 since we worked 0-based above; sparseMatrix (unlike underlying representation) is 1-based.
    A <- with( adj, sparseMatrix( i=i+1L, j=j+1L, x=x, dims=c(if(zeros){n*m}else{zrows[n*m]},n*m) ) )
    return(A)
}

grid.generator <- function (n,killing=0) {
    # random generator for RW with killing on square 2D grid
    A <- grid.adjacency(n)
    A@x <- rexp(length(A@x))
    A <- ( A + t(A) )
    diag(A) <- (-1)*rowSums( A - Diagonal(nrow(A),diag(A)) ) - killing
    return(A)
}

hitting.jacobi <- function (locs,G,hts,idG=1/rowSums(G),b=-1.0,tol=1e-6,kmax=1000) {
    # compute analytical expected hitting times using the Jacobi method (from jacobi.R)
    #  note that G ** comes with no diagonal **
    for (locnum in 1:length(locs)) {
        ll <- locs[locnum]
        k <- 1
        x <- hts[,locnum]
        x[ll] <- 0
        for (k in 1:kmax) {
            x_new <- idG * (G%*%x-b)
            x_new[ll] <- 0
            err <- mean((x_new-x)^2)
            # cat(k,":",err,"\n")
            if (err < tol) {
                cat("converged! err=", err, "\n")
                break; 
            }
            x <- x_new
        }
        if (k==kmax) { cat("Hit kmax. Did not converge, err=",err,"\n") }
        hts[,locnum] <- as.vector(x_new)
    }
    return(hts)
}

hitting.analytic <- function (locs, G, numcores=getcores()) {
    # compute analytical expected hitting times
    #   here `locs` is a vector of (single) locations
    #   or a list of vectors
    if ( numcores>1 && "parallel" %in% .packages()) {
        this.apply <- function (...) { do.call( cbind, mclapply( ..., mc.cores=numcores ) ) }
    } else {
        this.apply <- function (...) { sapply( ... ) }
    }
    hts <- this.apply( locs, function (k) { 
                klocs <- k[!is.na(k)]
                if (length(klocs)>0) {
                    z <- numeric(nrow(G))
                    z[-klocs] <- as.vector( solve( G[-klocs,-klocs], rep.int(-1.0,nrow(G)-length(klocs)) ) )
                    return( z )
                } else {
                    return(NA)
                }
            } )
    return(hts)
}

get.hitting.probs <- function (G,dG,neighborhoods,boundaries,numcores=getcores()) {
    # returns a list of matrices of with the [[k]]th has [i,j]th entry
    # the hitting probabilty from the i-th element of neighborhoods[[k]] to the j-th element of boundaries[[k]]
    mclapply( seq_along(neighborhoods), function (k) {
            nh <- neighborhoods[[k]]
            bd <- boundaries[[k]]
            as.matrix( solve( G[nh,nh]-Diagonal(n=length(nh),x=dG[nh]), -G[nh,bd,drop=FALSE] ) )
        }, mc.cores=numcores )
}

get.hitting.times <- function (G,dG,neighborhoods,boundaries,numcores=getcores()) {
    # returns a list of vectors with the [[k]]th has [i]th entry
    # the hitting times from the i-th element of neighborhoods[[k]] to boundaries[[k]]
    #  (like hitting.analytic but different syntax)
    mclapply( seq_along(neighborhoods), function (k) {
            nh <- neighborhoods[[k]]
            bd <- boundaries[[k]]
            as.vector( solve( G[nh,nh]-Diagonal(n=length(nh),x=dG[nh]), rep.int(-1.0,length(nh)) ) )
        }, mc.cores=numcores )
}

interp.hitting <- function ( G, locs, obs.hts, gamma=1 ) {
    # interpolate hitting times by minimizing squared error:
    #       G is a generator matrix
    #       locs is the indices of the rows of G for which we have data
    #       obs.hts is the (locs x locs) matrix of mean hitting times
    #       gamma is a fudge factor (so far unnecessary?)
    #   note that without the second 'crossprod' term in the defn of 'bvec'
    #   this finds the harmonic function interpolating the observed hitting times
    #   (or something close, I think)
    Pmat <- sparseMatrix( i=seq_along(locs), j=locs, x=1, dims=c(length(locs),nrow(G)) )
    PtP <- gamma * crossprod(Pmat)
    sapply( seq_along(locs), function (kk) {
                Gk <- G[-locs[kk],]
                bvec <- gamma * crossprod(Pmat,obs.hts[,kk]) - crossprod( Gk, rep(1.0,nrow(G)-1) )
                as.numeric( solve( PtP+crossprod(Gk), bvec ) )
    } )
}

make.G <- function (aa,AA) {
    G <- aa[1] * AA[[1]]
    if (length(AA)>1) for (k in 2:length(AA)) {
        G <- G + aa[k] * AA[[k]]
    }
    return(G)
}

estimate.expl <- function (hts, neighborhoods, layers, G, dG=rowSums(G), numcores=getcores() ) {
    # estimate parameters using the exponential transform
    ## deriv wrt gamma and delta : eqn:expl_deriv_gamma and eqn:expl_deriv_delta
    GH <- G %*% hts - dG * hts
    zeros <- unlist(neighborhoods) + rep((seq_along(neighborhoods)-1)*nrow(hts),sapply(neighborhoods,length))

    fn <- function (params) {

    }

    dd <- mclapply( 1:ncol(layers), function (k) {
                Z <- layers[,k] * GH * (GH+1)
                Z[zeros] <- 0
                dgamma <- 2*sum(Z)
                GLH <- G %*% ( layers[,k] * hts ) + dG * ((G>0)%*%layers[,k]) * hts 
                GLH[zeros] <- 0
                ddelta <- dgamma + 2*sum(GLH)
                return(c(dgamma,ddelta))
            } )

}

estimate.aa <- function (hts,locs,AA) {
    # Estimate alphas given full hitting times
    # don't count these cells:
    zeros <- locs + (0:(length(locs)-1))*nrow(hts)
    # here are the B^j, the C^j, Q, and b
    BB <- lapply( AA, "%*%", hts )
    CC <- sapply( BB, function (B) { B[zeros] <- 0; rowSums(B) } )
    b <- (-1) * colSums(CC) * ncol(hts)  # WHY THIS EXTRA FACTOR OF m?
    Q <- crossprod(CC)
    return( solve( Q, b ) )
}

iterate.aa <- function (aa,hts,locs,AA) {
    G <- make.G(aa,AA)
    # interpolate hitting times
    interp.hts <- interp.hitting( G, locs, hts )
    # infer aa from these
    estimate.aa(interp.hts,locs,AA)
}

###
# objective functions

# the integral equation
integral.objective <- function (env=environment()) {
    IL <- function (params) {
        # integral.hts is the mean hitting time of each neighborhood to its boundary,
        #  plus the mean hitting time to each neighborhood (including itself)
        update.aux(params,parent.env(environment()))
        hitting.probs <- get.hitting.probs( G, dG, neighborhoods[nonoverlapping], boundaries[nonoverlapping], numcores=numcores )
        hitting.times <- get.hitting.times( G, dG, neighborhoods[nonoverlapping], boundaries[nonoverlapping], numcores=numcores )
        integral.hts <- do.call( rbind, mclapply( seq_along(neighborhoods[nonoverlapping]), function (k) {
                ihs <- hitting.times[[k]] + hitting.probs[[k]] %*% hts[boundaries[[nonoverlapping[k]]],nonoverlapping] 
                ihs[,k] <- 0
                return(ihs)
            }, mc.cores=numcores ) )
        ans <- sum( ( hts[unlist(neighborhoods[nonoverlapping]),nonoverlapping] / integral.hts - 1 )^2, na.rm=TRUE )  # RATIO!
        # ans <- sum( ( hts[unlist(neighborhoods[nonoverlapping]),nonoverlapping] - integral.hts )^2, na.rm=TRUE )
        if (!is.finite(ans)) { browser() }
        return(ans)
    }
    environment(IL) <- env
    return(IL)
}

# the differential equation
differential.objective <- function (env=environment) {
    L <- function (params) {
        update.aux(params,parent.env(environment()))
        ans <- ( sum( weightings*rowSums((GH+sc.one)^2) ) - (nomitted)*sc.one^2 )
        if (!is.finite(ans)) { browser() }
        return(ans)
    }
    dL <- function (params) {
        update.aux(params,parent.env(environment()))
        bgrad <- ( 2 / params[1] )* sum( weightings * rowSums(GH * (GH+sc.one)) )
        ggrads <- sapply( 1:ncol(layers), function (kk) {
                2 * sum( weightings * rowSums( (layers[,kk] * GH) * (GH+sc.one)) )
            } )
        dgrads <- ggrads + sapply( 1:ncol(layers), function (kk) {
                GL <- G
                GL@x <- G@x * layers[Gjj,kk]
                dGL <- rowSums(GL)
                GLH <- GL %*% hts - dGL*hts
                GLH[zeros] <- 0
                return( 2 * sum( weightings * rowSums( GLH * (GH+sc.one) )  ) )
            } )
        ans <- ( c(bgrad, ggrads, dgrads) )
        if (any(!is.finite(ans))) { browser() }
        return(ans)
    }
    environment(L) <- environment(dL)  <- env
    return(list(L=L,dL=dL))
}


########
# Raster whatnot

get.neighborhoods <- function ( ndist, locations, nonmissing, layer, numcores=getcores(), na.rm=TRUE ) {
    neighborhoods <- mclapply( seq_along(locations) , function (k) {
        d_tort <- distanceFromPoints( layer, locations[k] )
        match( Which( d_tort <= max(ndist,minValue(d_tort)), cells=TRUE, na.rm=TRUE ), nonmissing )
    }, mc.cores=numcores )
    if (na.rm) { neighborhoods <- lapply(neighborhoods,function (x) { x[!is.na(x)] }) }
    return(neighborhoods)
}


get.boundaries <- function ( neighborhoods, nonmissing, layer, numcores=getcores(), na.rm=TRUE ) {
    boundaries <- mclapply( neighborhoods, function (nh) {
        values(layer) <- TRUE
        values(layer)[nonmissing][nh] <- NA
        bdry <- boundaries(layer,directions=4)
        match( which( (!is.na(values(bdry))) & (values(bdry)==1) ), nonmissing )
    }, mc.cores=numcores )
    if (na.rm) { boundaries <- lapply(boundaries,function (x) { x[!is.na(x)] }) }
    return(boundaries)
}

which.nonoverlapping <- function (neighborhoods) {
    # find a set of neighborhoods that are mutually nonoverlapping
    perm <- sample(length(neighborhoods))
    goodones <- rep(FALSE,length(perm))
    goodones[1] <- TRUE
    for (k in seq_along(perm)[-1]) {
        goodones[k] <- ( 0 == length( intersect( neighborhoods[[k]], unlist(neighborhoods[goodones]) ) ) )
    }
    return( which(goodones) )
}

upsample <- function ( layer.vals, ag.fact, layer.1, nonmissing.1, layer.2, nonmissing.2, checkit=FALSE ) {
    # moves from layer.1 to layer.2, which must be related by a factor of ag.fact
    values(layer.1)[nonmissing.1] <- layer.vals
    layer.1.dis <- crop( disaggregate( layer.1, fact=ag.fact, method='bilinear' ), layer.2 )
    stopifnot( all( dim(layer.1.dis)==dim(layer.2) ) )
    # can skip this step, hopefully
    if (checkit) {
        layer.1.dis.res <- resample( layer.1.dis, layer.2 )
        stopifnot( all( abs( values(layer.1.dis)[nonmissing.2] - values(layer.1.dis.res)[nonmissing.2] ) < 1e-3 ) )
    }
    # get values out
    return( values(layer.1.dis)[nonmissing.2] )
}

upsample.hts <- function ( hts, ..., numcores=getcores() ) {
    new.hts <- do.call( cbind, mclapply( 1:ncol(hts), function (k) {
                upsample( hts[,k], ... )
        }, mc.cores=numcores ) )
    colnames(new.hts) <- colnames(hts)
    return(new.hts)
}

downsample <- function ( layer.vals, ag.fact, layer.1, nonmissing.1, layer.2, nonmissing.2, checkit=FALSE ) {
    # moves from layer.2 to layer.1, which must be related by a factor of ag.fact
    values(layer.2)[nonmissing.2] <- layer.vals
    layer.2.ag <- crop( aggregate( layer.2, fact=ag.fact, fun=mean, na.rm=TRUE ), layer.1 )
    stopifnot( all( dim(layer.2.ag)==dim(layer.1) ) )
    # get values out
    return( values(layer.2.ag)[nonmissing.1] )
}

downsample.hts <- function ( hts, ..., numcores=getcores() ) {
    new.hts <- do.call( cbind, mclapply( 1:ncol(hts), function (k) {
                downsample( hts[,k], ... )
        }, mc.cores=numcores ) )
    colnames(new.hts) <- colnames(hts)
    return(new.hts)
}

##
# misc

selfname <- function (x) { names(x) <- make.names(x); x }

##
# plotting whatnot

plot.ht.fn <- function (layer.prefix,layer.name,nonmissing,layer=raster(paste(layer.prefix,layer.name,sep='')),homedir="..",par.args=list(mar=c(5,4,4,7)+.1)) {
    # use this to make a quick plotting function
    values(layer)[-nonmissing] <- NA # NOTE '-' NOT '!'
    load(paste(homedir,"tort_180_info/tort.coords.rasterGCS.Robj",sep='/'))
    ph <- function (x,...) { 
        values(layer)[nonmissing] <- x
        opar <- par(par.args)  # plotting layers messes up margins
        plot(layer,...)
        points(tort.coords.rasterGCS,pch=20,cex=.25)
        par(opar)
    }
    environment(ph) <- new.env()
    assign("tort.coords.rasterGCS",tort.coords.rasterGCS,environment(ph))
    return(ph)
}

colorize <- function (x, nc=32, colfn=function (n) rainbow_hcl(n,c=100,l=50), zero=FALSE, trim=0, breaks, return.breaks=FALSE) {
    if (is.numeric(x) & trim>0) {
        x[ x<quantile(x,trim,na.rm=TRUE) ] <- quantile(x,trim,na.rm=TRUE)
        x[ x>quantile(x,1-trim,na.rm=TRUE) ] <- quantile(x,1-trim,na.rm=TRUE)
    }
    if (missing(breaks) & is.numeric(x)) {
        if (zero) {
            breaks <- seq( (-1)*max(abs(x),na.rm=TRUE), max(abs(x),na.rm=TRUE), length.out=nc )
        } else {
            breaks <- seq( min(x,na.rm=TRUE), max(x,na.rm=TRUE), length.out=nc )
        }
        x <- cut(x,breaks=breaks,include.lowest=TRUE)
    } else {
        x <- factor(x)
    }
    if (return.breaks) {
        return(breaks)
    } else {
        return( colfn(nlevels(x))[as.numeric(x)] )
    }
}
