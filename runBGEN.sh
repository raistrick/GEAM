#!/bin/bash

# functions
function join { local IFS="$1"; shift; echo "$*"; }

# get arguments
while [[ $# > 1 ]]
do
  key="$1"

  case $key in
    -d|--data) # path to the top level of dataset
    DATASETPATH="$2"
    echo "DATASETPATH=$DATASETPATH"
    shift
     ;;
    -v|--variables) # path to variable list 
    VARSPATH="$2"
    echo "VARSPATH=$VARSPATH"
    OUTFORMAT="gen"
    shift 
    ;;
    -s|--samples) # path to sample list
    SAMPLESPATH="$2"
    echo "SAMPLESPATH=$SAMPLESPATH"
    shift 
    ;;
    -g|--group) # mother/children
    GROUP="$2"
    echo "GROUP=$GROUP"
    shift
    ;;
    -n|--new) # path to new directory
    NEWPATH="$2"
    echo "NEWPATH=$NEWPATH"
    shift 
    ;;
    -b|--bnumber) # project B number
    BNUM="$2"
    echo "BNUM=$BNUM"
    shift
    ;;
    *)
    ;;
    esac
  shift
done

# Projects should have a "B number" in format B1234
# Setting the BNUM to anything else can override this
# if no BNUM then set as B0000
if [[ -z "$BNUM" ]]; then
  BNUM="B0000"
fi

# if directory exists, exit
# else create directory structure
# ensures that other projects are not accidentally overwritten
if [ -d $NEWPATH ]
then
  echo "$NEWPATH already exists, exiting"
  exit
else 
  mkdir -p $NEWPATH/jobs
  touch $NEWPATH/jobs/run.sh
fi

# check what the group options are
# this is necessary for removing withdrawn consent
# valid options for perl script are "all", "mothers" and "children"
if [[ -n "$GROUP" ]]; then
  echo "Getting sample list for group $GROUP"
  perl getSampleForSet.pl $DATASETPATH/data/data.sample $GROUP $NEWPATH ' '
  echo "...Done"
  SAMPLESPATH="$NEWPATH/data.set"
else 
  echo "Getting sample list for group all"
  perl getSampleForSet.pl $DATASETPATH/data/data.sample all $NEWPATH ' '
  echo "...Done"
  SAMPLESPATH="$NEWPATH/data.set"
fi

# get samples
# this uses the data.set file, where withdrawn consent individuals will have been removed
# if a file is defined already (manually) then this overrides the withdrawn consent list
# 
incl_samples=""
if [[ -n "$SAMPLESPATH" ]]
then
  # if path is a file, include
  # else use dample file
  if [[ -f $SAMPLESPATH ]]; then
    incl_samples="-incl-samples $SAMPLESPATH"
  else
    echo "--samples path invalid, ignoring"
    cp $DATASETPATH/data/data.sample $NEWPATH/data.set
  fi
else
  # whole set
  cp $DATASETPATH/data/data.sample $NEWPATH/data.set
fi

# if variable list defined (rs numbers and "chr:pos_allele1_allele2" ids)
# use snp-stats to get alternative IDs for inclusion as -incl-snpids and -incl-rsids
incl_snps=""
if [ -n "$VARSPATH" ]
then
  echo "Running SNP list: $VARSPATH"

  # get snp-stats for variables
  touch $NEWPATH/jobs/req_list.snp-stats
  touch $NEWPATH/jobs/req_list.not-found
  cp $VARSPATH $NEWPATH/jobs/req_list.all
  while read -r line || [[ -n "$line" ]]; do
    #grep -h "$line\s" $DATASETPATH/data/snp-stats/*.snp-stats >> $NEWPATH/jobs/req_list.snp-stats
    res=$(grep -h "$line\s" $DATASETPATH/data/snp-stats/*.snp-stats)
    if [[ $res == "" ]]; then
      echo "$line" >> $NEWPATH/jobs/req_list.not-found
    else
      echo "$res" >> $NEWPATH/jobs/req_list.snp-stats
    fi
  done < "$NEWPATH/jobs/req_list.all"
  
  # cut first column to snpids
  cut -d ' ' -f 1  $NEWPATH/jobs/req_list.snp-stats > $NEWPATH/jobs/req_list.snpids.temp
  touch $NEWPATH/jobs/req_list.snpids

  # remove where format of SNP ID is incorrect
  while read -r line || [[ -n "$line" ]]; do
                if [[ $line =~ ^[0-9]+\:[0-9]+\_ ]]; then
      echo "$line" >> $NEWPATH/jobs/req_list.snpids
    fi
        done < "$NEWPATH/jobs/req_list.snpids.temp"
  rm $NEWPATH/jobs/req_list.snpids.temp

  # cut second column to rsids
  cut -d ' ' -f 2 $NEWPATH/jobs/req_list.snp-stats > $NEWPATH/jobs/req_list.rsids

  incl_snps="-incl-snpids $NEWPATH/jobs/req_list.snpids -incl-rsids $NEWPATH/jobs/req_list.rsids"
else
  echo "Running whole set"  
fi

# copy sample include file
#if [ -n "$SAMPLESPATH" ]; then
#  echo "for some reason creating data.selection - $SAMPLESPATH"
#  cp $SAMPLESPATH $NEWPATH/data.selection
#else
#  echo "for somre reason coping data.sample??"
#  cp $DATASETPATH/data/data.sample $NEWPATH/data.sample
#fi

# loop through directory of dosage_bgen files
for filename in $DATASETPATH/data/dosage_bgen/*.bgen; do
  fbname=$(basename "$filename")
  
  # switch format
        if [[ -n $OUTFORMAT ]]; then
                fbname=$(echo $fbname | sed -e 's/\.bgen$/\.gen/')
        fi
  
  # add to run script
  echo -e "qsub $NEWPATH/jobs/$fbname.sh\n" >> $NEWPATH/jobs/run.sh

  # create job script
  cat job_header.txt > $NEWPATH/jobs/$fbname.sh
  sed -i "s/Job/$BNUM\-$fbname/" $NEWPATH/jobs/$fbname.sh
  echo "module add apps/qctool-1.3" >> $NEWPATH/jobs/$fbname.sh
  echo "time qctool -g $filename -og $NEWPATH/$fbname -os $NEWPATH/$fbname.sample -s $DATASETPATH/data/data.sample $incl_snps $incl_samples" >> $NEWPATH/jobs/$fbname.sh
done


# write combine script 
# ONLY NECESSARY FOR .gen files
mkdir -p $NEWPATH/export/data
if [[ -n $OUTFORMAT ]]; then
  cat job_header.txt > $NEWPATH/jobs/convert.sh
  echo "function join { local IFS=\\\"\$1\\\"; shift; echo \\\"\$*\\\"; }" >> $NEWPATH/jobs/convert.sh
  echo "GS=()" >> $NEWPATH/jobs/convert.sh
  echo "for filename in $NEWPATH/*.gen; do" >> $NEWPATH/jobs/convert.sh
  echo "  if [[ ! -s \$filename ]]; then" >> $NEWPATH/jobs/convert.sh
  echo "    rm -f \$filename" >> $NEWPATH/jobs/convert.sh
  echo "    rm -f \$filename.sample" >> $NEWPATH/jobs/convert.sh
  echo "  else" >> $NEWPATH/jobs/convert.sh
  echo "    GS+=(\"\$filename\")" >> $NEWPATH/jobs/convert.sh
  echo "  fi" >> $NEWPATH/jobs/convert.sh
  echo "done" >> $NEWPATH/jobs/convert.sh
  echo "a=$(join ' ' \"\${GS[\@]}\")" >> $NEWPATH/jobs/convert.sh
  echo "cat \$a > $NEWPATH/export/data/data.gen" >> $NEWPATH/jobs/convert.sh
  echo "for filename in $NEWPATH/*.sample; do" >> $NEWPATH/jobs/convert.sh
  echo "  if [ ! -f $NEWPATH/export/data/data.sample ]; then" >> $NEWPATH/jobs/convert.sh
  echo "    cp \$filename $NEWPATH/export/data/data.sample" >> $NEWPATH/jobs/convert.sh
  echo "    cut -d ' ' -f 1-2 \$filename > $NEWPATH/export/data/data.sample.temp" >> $NEWPATH/jobs/convert.sh
  echo "  else" >> $NEWPATH/jobs/convert.sh
  echo "    cut -d ' ' -f 1-2 \$filename > \$filename.temp" >> $NEWPATH/jobs/convert.sh
  echo "    diff=\$(diff $NEWPATH/export/data/data.sample.temp \$filename.temp)" >> $NEWPATH/jobs/convert.sh
  echo "    if [ \"\$diff\" != '' ]; then" >> $NEWPATH/jobs/convert.sh
  echo "      echo \"\$filename does not match, terminating\"" >> $NEWPATH/jobs/convert.sh
  echo "      exit" >> $NEWPATH/jobs/convert.sh
  echo "    else" >> $NEWPATH/jobs/convert.sh
  echo "      echo \"\$filename matches\"" >> $NEWPATH/jobs/convert.sh
  echo "      rm \$filename.temp" >> $NEWPATH/jobs/convert.sh
  echo "    fi" >> $NEWPATH/jobs/convert.sh
  echo "  fi" >> $NEWPATH/jobs/convert.sh
  echo "done" >> $NEWPATH/jobs/convert.sh
  echo "rm $NEWPATH/export/data/data.sample.temp" >> $NEWPATH/jobs/convert.sh
  echo "perl ~/swapIDs.pl $NEWPATH/export/data/data.sample ~/collab_ids/cid$BNUM.csv ' '" >> $NEWPATH/jobs/convert.sh
else
  cat job_header.txt > $NEWPATH/jobs/convert.sh
  echo "for filename in $NEWPATH/*.bgen; do" >> $NEWPATH/jobs/convert.sh
  echo "  fbname=\$(basename \"\$filename\")" >> $NEWPATH/jobs/convert.sh
        echo "  if [[ ! -s \$filename ]]; then" >> $NEWPATH/jobs/convert.sh
        echo "    rm -f \$filename" >> $NEWPATH/jobs/convert.sh
        echo "    rm -f \$filename.sample" >> $NEWPATH/jobs/convert.sh
        echo "  else" >> $NEWPATH/jobs/convert.sh
        echo "    mv \$filename $NEWPATH/export/data/\$fbname" >> $NEWPATH/jobs/convert.sh
        echo "  fi" >> $NEWPATH/jobs/convert.sh
        echo "done" >> $NEWPATH/jobs/convert.sh
        echo "for filename in $NEWPATH/*.sample; do" >> $NEWPATH/jobs/convert.sh
        echo "  if [ ! -f $NEWPATH/export/data/data.sample ]; then" >> $NEWPATH/jobs/convert.sh
        echo "    cut -d ' ' -f 1-2 \$filename > $NEWPATH/export/data/data.sample.temp" >> $NEWPATH/jobs/convert.sh
  echo "    mv \$filename $NEWPATH/export/data/data.sample" >> $NEWPATH/jobs/convert.sh
        echo "  else" >> $NEWPATH/jobs/convert.sh
        echo "    cut -d ' ' -f 1-2 \$filename > \$filename.temp" >> $NEWPATH/jobs/convert.sh
        echo "    diff=\$(diff $NEWPATH/export/data/data.sample.temp \$filename.temp)" >> $NEWPATH/jobs/convert.sh
        echo "    if [ \"\$diff\" != '' ]; then" >> $NEWPATH/jobs/convert.sh
        echo "      echo \"\$filename does not match, terminating\"" >> $NEWPATH/jobs/convert.sh
        echo "      exit" >> $NEWPATH/jobs/convert.sh
        echo "    else" >> $NEWPATH/jobs/convert.sh
        echo "      echo \"\$filename matches\"" >> $NEWPATH/jobs/convert.sh
  echo "      rm \$filename" >> $NEWPATH/jobs/convert.sh
        echo "      rm \$filename.temp" >> $NEWPATH/jobs/convert.sh
        echo "    fi" >> $NEWPATH/jobs/convert.sh
        echo "  fi" >> $NEWPATH/jobs/convert.sh
        echo "done" >> $NEWPATH/jobs/convert.sh
        echo "rm $NEWPATH/export/data/data.sample.temp" >> $NEWPATH/jobs/convert.sh
  echo "perl ~/swapIDs.pl $NEWPATH/export/data/data.sample ~/collab_ids/cid$BNUM.csv ' '" >> $NEWPATH/jobs/convert.sh
fi

# copy docs to export
cp -r $DATASETPATH/docs $NEWPATH/export

# change permissions
chmod 700 $NEWPATH/jobs/*

# declare complete
echo "SCRIPT COMPLETE"
