# compute for each N, M, the chance of picking different alleles
#  from the Nth and Mth pairs of columns
# weighted by geometric mean of corresponding even rows

{ 
    for ( N=1; N<=(NF/2); N++ ) { 
        D[N] = ( $(2*N-1) + $(2*N)  );  # total coverage
        if ( D[N] > 0) {
            P[N] = $(2*N-1) / D[N];  # major allele freq
            if ( D[N] > 1 ) {
                if (D[N] < 10) { # Set a maximum of 9 reads for N
                    WW = D[N]*(D[N]-1) ;   # weights
                    W[N,N] += WW;
                    PI[N,N] += 2 * WW * P[N] * ( D[N] - $(2*N-1) ) / (D[N]-1) ;  # prob of difference
                }
            }
            for ( M=1; M<N; M++ ) {
                if (D[M] > 0) {  # Set a maximum of 9 reads for M
                    if (D[M] < 10) {
                        WW = D[N]*D[M] ;
                        W[N,M] += WW;
                        PI[N,M] += ( P[N]*(1-P[M]) + P[M]*(1-P[N]) ) * WW;
                    }
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
