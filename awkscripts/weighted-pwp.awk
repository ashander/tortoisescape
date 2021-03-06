# compute for each N, M, the chance of picking different alleles
#  from the Nth and Mth pairs of columns
# weighted by geometric mean of corresponding even rows

{ 
    for ( N=1; N<=(NF/2); N++ ) { 
        D[N] = ( $(2*N-1) + $(2*N)  );  # total coverage
        if ( D[N] > 0 ) {
            P[N] = $(2*N-1) / D[N];  # major allele freq
            if ( D[N] > 1 ) {
                WW = D[N]*(D[N]-1) ;
                W[N,N] += WW ;   # weights
                PI[N,N] += WW * ( 2 * P[N] * ( D[N] - $(2*N-1) ) / (D[N]-1) ) ;  # prob of difference
            }
            for ( M=1; M<N; M++ ) {
                if (D[M] > 0) {
                    WW = D[N]*D[M] ;
                    W[N,M] += WW;
                    PI[N,M] += WW * ( P[N]*(1-P[M]) + P[M]*(1-P[N]) ) ;
                }
            }
        }
    }
}

END { 
    for ( N=1; N<=(NF/2); N++ ) { 
        for ( M=1; M<=N; M++ ) { 
            print ( W[N,M]>0 ? PI[N,M]/W[N,M] : "NA" ); 
        } 
    } 
}
