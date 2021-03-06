#!/usr/bin/Rscript

source("resistance-fns.R")
source("testing-fns.R")

# width of square grid
n <- 100
nmap <- matrix(1:n^2,nrow=n)
all.locs <- cbind( i=as.vector(row(nmap)), j=as.vector(col(nmap)) )

# random landscape
n.layers <- 2
AA <- replicate( n.layers, grid.generator(n), simplify=FALSE )
aa <- rep(1/n.layers,length=n.layers)
G <- aa[1] * AA[[1]]
for (k in 2:n.layers) {
    G <- G + aa[k] * AA[[k]]
}


# sampling locations
nsamps <- 100
locs.ij <- cbind( i=sample.int(n,nsamps)-1L, j=sample.int(n,nsamps)-1L )
locs <- ij.to.k(locs.ij,n,n)

# analytical mean hitting times
true.hts <- hitting.analytic(locs,G)  # warning, this could take a while (10s for n=100 and nsamps=20)

# Observed hitting times
pairwise.hts <- true.hts[locs,]

####
# iterate:

### 0)
# guess, wildly
a0 <- c(20,20)
# the following is equivalent to
# a1 <- iterate.aa(a0,pairwise.hts,locs,AA)

G.est <- make.G(a0,AA)

### 1)
# interpolate hitting times
interp.hts <- interp.hitting( G.est, locs, pairwise.hts )

### 2)
# infer aa
a1 <- estimate.aa(interp.hts,locs,AA)

# check interpolation:
layout(t(1:2))
while( !is.null(locator(n=1)) ) {
    kk <- sample.int(length(locs),1)
    plot.ht(true.hts[,kk])
    plot.ht(interp.hts[,kk])
}

###
# get grid of where parameters map to:
if (FALSE) {
# TAKES A LONG TIME
agrid <- expand.grid( a0=seq(.01,10,length.out=40), a1=seq(.01,10,length.out=40) )
bgrid <- t( apply(agrid,1,function(a0) { iterate.aa(a0,pairwise.hts,locs,AA) } ) )
colnames(bgrid) <- c("b0","b1")

plot( 0, 0, xlim=range(agrid$a0), ylim=range(agrid$a1), type='n', xlab='', ylab='' )
arrows( x0=agrid[,1], y0=agrid[,2], x1=bgrid[,1], y1=bgrid[,2], length=0.1 )
points( aa[1], aa[2], pch="*", col="red", cex=2 )

write.table( cbind(agrid,bgrid), file="abgrid.csv", sep=",", row.names=FALSE )
}
