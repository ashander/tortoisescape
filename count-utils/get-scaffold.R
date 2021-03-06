#!/usr/bin/env Rscript

usage <- "Usage:\
    get-scaffold.R (name of counts file) (name of scaffold) > output\
Assumes that if the counts file is\
  the-counts-file.counts.bin.gz
then there is also\
  the-counts-file.counts.header\
  the-counts-file.pos.gz\
containing information about columns and rows, respectively.
"


arglist <- if (interactive()) { scan(what='') } else { commandArgs(TRUE) }

if (length(arglist)!=2) { stop(usage) }
countfile <- arglist[1]
scaffold <- arglist[2]

posfile <- paste0(gsub("[.]counts[.].*","",countfile),".pos.gz")
if (!file.exists(posfile)) { stop(sprintf("Cannot find position file %s", posfile)) }
awkscript <- sprintf("zcat %s | awk 'BEGIN {z=0} /%s/ {if (z==0) print FNR; z=1} !/%s/ {if (z==1) { print FNR; z=2; exit} } END { if (z==1) { print FNR+1 } }'", posfile, scaffold, scaffold)
# minus one for the header
awkcon <- pipe(awkscript)
scaf_lines <- scan(awkcon) - 1
close(awkcon)

# cat(sprintf("Reading from %d to %d\n", scaf_lines[1], scaf_lines[2]), file=stderr())

# the count file
if (grepl(".counts.gz$",countfile)) {
    count.con <- gzfile(countfile,open="r")
    count.header <- scan(count.con,nlines=1,what="char")
    read_fun <- function (start, end) { scan(count.con, skip=start-1, nlines=end-start) }
} else if (grepl("counts.bin",countfile)) {
    count.header <- scan(paste0(gsub(".gz$","",countfile),".header"),what="char")
    count.ids <- do.call(rbind,strsplit(count.header,"_"))
    colnames(count.ids) <- c("angsd.id","base")
    nindivs <- nrow(count.ids)/4
    line_length <- 4*nindivs
    # seek is NOT WORKING for large gzip files
    is_gzip <- grepl(".gz$",countfile)
    # count.con <- if (!grepl(".counts.bin.gz$",countfile)) { file(countfile,open="rb") } else { gzfile(countfile,open="rb") }
    bash <- sprintf("%scat %s | tail -c+%0.0f", if (is_gzip) "z" else "", countfile, 1+(scaf_lines[1]-1)*line_length)
    count.con <- pipe(bash, open='rb')
    attr(count.con,"nindivs") <- nindivs
    attr(count.con,"nbytes") <- 1
    # Read the lines from start to end, inclusive.
    read_fun <- function (start, end) {
        # note that seek on gzfiles starts at zero and only moves forwards
        #  --> zero-based index
        ## this is done by head/tail above
        ## seek(count.con, where=(start-1)*line_length, rw="r")
        readBin( count.con, what=integer(),
                  n=line_length*(end-start),
                  size=attr(count.con,"nbytes"),
                  signed=(attr(count.con,"nbytes")>2) )
    }
} else { stop(paste("Counts file", countfile, "not a recognized format.")) }

out <- read_fun(scaf_lines[1], scaf_lines[2])
# dim(out) <- c(line_length, end-start+1)

close(count.con)

write(out, file=stdout(), ncolumns=4*nindivs)
