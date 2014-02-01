#assert existence of
#commonfile
source(commonfile)
#pwmfile
load(file.path(pwmdir,paste0(pwmid,'.pwmout.RData')))
#tmpdir
load(file.path(tmpdir,paste0(pwmid,'.svout.RData')))
#outdir

#####
# make call



validpos = list.files(tmpdir,paste0('positive.tf',pwmid,'-'))
chrids=match(sapply(strsplit(validpos,'[.-]'),function(i){i[3]}),ncoords)

evalsvs <- function(pos.mat,neg.mat,wt){
    #svps=t(filtermat.pos%*%wt[(1:(2*wsize))+2])%*%pos.mat
    svps=wt[(1:(2*wsize))+2]%*%pos.mat
    #svns=t(filtermat.neg%*%wt[(2*wsize+1):(4*wsize)+2])%*%neg.mat
    svns=wt[(2*wsize+1):(4*wsize)+2]%*%neg.mat
    svps + svns + wt[1] + (colSums(pos.mat>0)+colSums(neg.mat>0)+1) * wt[2]
}

posbgct = rep(0,2*wsize)

neglis=do.call(c,lapply(list.files(tmpdir,paste0('background.tf',pwmid,'-')),function(i){
    print(i)
    load(file.path(tmpdir,i))
    posbgct <<- posbgct + rowSums(pos.mat)
    as.double(evalsvs(pos.mat,neg.mat,sv.rotate))
}))

rowsizes = rep(0,length(validpos))
posct=rep(0,2*wsize)
negct=rep(0,2*wsize)

for(i in 1:length(validpos)){
    print(i)
    load(file.path(tmpdir,validpos[i]))
    posct = posct + rowSums(pos.mat)
    negct = negct + rowSums(neg.mat)
    tct=colSums(pos.mat)+colSums(neg.mat)
    rowsizes[i]=ncol(pos.mat)
    pws=coords.pwm[[chrids[i]]]
    sv.score = as.double(evalsvs(pos.mat,neg.mat,sv.rotate))
    outputs=cbind(sv.score,tct,pws)
    writeBin(as.vector(outputs),paste0(outdir,ncoords[chrids[i]],'.out.bin'),4)
}

readonecol <- function(filename,rowsize,colsel){
    con=file(filename,open='rb')
    seek(con,4*rowsize*(colsel-1))
    rb=readBin(con,double(),n=rowsize,size=4)
    close(con)
    rb
}

allsvs=do.call(c,lapply(1:length(validpos),function(i){
    readonecol(file.path(outdir,paste0('tf.',pwmid,'-',ncoords[chrids[i]],'.out.bin')),rowsizes[i],1)
}))

allpws=do.call(c,lapply(1:length(validpos),function(i){
    readonecol(file.path(outdir,paste0('tf.',pwmid,'-',ncoords[chrids[i]],'.out.bin')),rowsizes[i],3)
}))


capf <- function(x,cap=2){y=x;y[y<0]=1e-10;log(y+1e-10)}


nenrich <- function(x){
    opp=getopp(x)
    opp$objective
}

getopp <- function(x){
    rs=allpws+capf(allsvs)*x
    sorted=sort(rs,decreasing=T)
    vcut=(pwb+capf(neglis)*x)
    svcut = sort(vcut)
    maxl=min(50000,length(sorted))
    ops=(length(svcut)-findInterval(sorted[100:maxl],svcut)+10)/(100:maxl)
    list(objective=min(ops),minimum=which.min(ops))
}

lnsrch <- function(i,sorted,svcut,regr=100){
    (length(svcut)-findInterval(sorted[i],svcut)+regr)/i
}

pwb = sample(allpws,length(allpws))

stepsz=0.1
alloptim=sapply(seq(0,10,by=stepsz),nenrich)#
opt.pwm.weight=optimize(nenrich,c(-stepsz,stepsz)+(which.min(alloptim)-1)*stepsz)

scores=allpws+capf(allsvs)*opt.pwm.weight$minimum
num.passed=getopp(opt.pwm.weight$minimum)$minimum+100-1
cutoff.val=sort(scores,decreasing=T)[num.passed]
passed.cutoff=scores > cutoff.val

print(num.passed)

chrs.vec=do.call(c,lapply(1:length(validpos),function(i){
    rep(ncoords[chrids[i]],length(coords[[chrids[i]]]))
}))
coords.vec=do.call(c,lapply(1:length(validpos),function(i){
    start(coords[[chrids[i]]])
}))

df.all=data.frame(chr=chrs.vec,coord=coords.vec,pwm=allpws,shape=allsvs,score=scores)
df.bg=df.all[passed.cutoff,]

write.csv(df.bg,file=paste0(outdir,'calls.csv'))
write.csv(df.all,file=paste0(outdir,'calls.all.csv'))


pdf(paste0(outdir,'diag.pdf'))
plot(seq(0,10,by=stepsz),alloptim,type='l')
spos = scores
npos = pwb+capf(neglis)*opt.pwm.weight$minimum
multhist(list(spos[spos > 0 & npos >0],npos[spos > 0 & npos > 0]),breaks=80)
hist(allpws)
hist(log(allsvs[allsvs>0]),100)
plot(allpws,allsvs,pch=c('.',20)[passed.cutoff+1],log='y')
points(sample(allpws,length(allpws)),neglis,pch='.',log='y',col='red')
dev.off()

