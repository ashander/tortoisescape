jacobi <- function(D_R,D_1b,tol=1e-6){
    # solves Ax = b
    # where D_1b is the inverse of the diagonal of A, multiplied by b
    #  and D_R is the inverse of the diagonal of A, multiplied by (-1) times the offdiagonal of A:
    # D_1b <- b/diag(A)
    # D_R <- (-1) * 1/diag(A) * (A - diag(A))

    kmax <- 10000 #maximum iterations
    err <- 1 
    x = rnorm(length(D_1b),0,1) # starting vector
    k <- 1

    while(k < kmax && err > tol && err < 2^16){
        x_new <- D_R%*%x + D_1b
        err <- sum((x_new-x)^2)/length(x)
        x <- x_new
        k <- k + 1
    }
    return(x)
}
