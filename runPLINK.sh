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

# Project should have a "B number" in the format B1234
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
  if [ -r $DATASETPATH/data/bestguess/data.fam ]; then
    perl getSampleForSet.pl $DATASETPATH/data/bestguess/data.fam $GROUP $NEWPATH ' '
  elif [ -r $DATASETPATH/data/bestguess/data_chr01.fam ]; then
    perl getSampleForSet.pl $DATASETPATH/data/bestguess/data_chr01.fam $GROUP $NEWPATH ' '
  else 
    echo "$DATASETPATH/data/bestguess/data.fam or $DATASETPATH/data/bestguess/data_chr01.fam, exiting"
    exit
  fi
  echo "...Done"
  SAMPLESPATH="$NEWPATH/data.set"
else 
  echo "Getting sample list for group all"
  perl getSampleForSet.pl $DATASETPATH/data/bestguess/data.fam all $NEWPATH ' '
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
  # else use sample file
  if [[ -f $SAMPLESPATH ]]; then
    incl_samples="--keep $SAMPLESPATH"
  else
    echo "--samples path invalid, ignoring"
    incl_samples="--keep $NEWPATH/data.set"
  fi
else
  # whole set
  incl_samples="--keep $NEWPATH/data.set"
fi

# if variable list defined (rs numbers and "chr:pos_allele1_allele2" ids)
# use snp-stats to get alternative IDs for inclusion as -incl-snpids and -incl-rsids
incl_snps=""
if [ -n "$VARSPATH" ]
then
  echo "Running SNP list: $VARSPATH"

  # get snp-stats for variables
  touch $NEWPATH/jobs/req_list.found
  touch $NEWPATH/jobs/req_list.not-found
  cp $VARSPATH $NEWPATH/jobs/req_list.all
  while read -r line || [[ -n "$line" ]]; do
    #grep -h "$line\s" $DATASETPATH/data/bestguess/*.bim >> $NEWPATH/jobs/req_list.found
    res=$(grep -h "$line\s" $DATASETPATH/data/bestguess/*.bim)
    if [[ $res == "" ]]; then
      echo "$line" >> $NEWPATH/jobs/req_list.not-found
    else
      echo $res | awk '{print $2}' >> $NEWPATH/jobs/req_list.found
      #echo "$res" >> $NEWPATH/jobs/req_list.found
    fi
  done < "$NEWPATH/jobs/req_list.all"

  incl_snps="--extract $NEWPATH/jobs/req_list.found"
else
  echo "Running whole set"  
fi

# loop through directory of dosage_bgen files
mkdir -p $NEWPATH/export/data
for filename in $DATASETPATH/data/bestguess/*.bed; do
  fbname=$(basename "$filename")
  fbname2=${fbname%.*}
  
  # add to run script
  echo -e "qsub $NEWPATH/jobs/$fbname2.sh\n" >> $NEWPATH/jobs/run.sh

  # create job script
  cat job_header.txt > $NEWPATH/jobs/$fbname2.sh
  sed -i "s/Job/$BNUM\-$fbname2/" $NEWPATH/jobs/$fbname2.sh
  echo "module add apps/plink-1.90" >> $NEWPATH/jobs/$fbname2.sh
  echo "time plink --bfile $DATASETPATH/data/bestguess/$fbname2 --make-bed --out $NEWPATH/export/data/$fbname2 $incl_snps $incl_samples" >> $NEWPATH/jobs/$fbname2.sh
done

# write combine script 
cat job_header.txt > $NEWPATH/jobs/convert.sh
echo "function join { local IFS=\\\"\$1\\\"; shift; echo \\\"\$*\\\"; }" >> $NEWPATH/jobs/convert.sh
#  echo "GS=()" >> $NEWPATH/jobs/convert.sh
#  echo "for filename in $NEWPATH/*.gen; do" >> $NEWPATH/jobs/convert.sh
#  echo "  if [[ ! -s \$filename ]]; then" >> $NEWPATH/jobs/convert.sh
#  echo "    rm -f \$filename" >> $NEWPATH/jobs/convert.sh
#  echo "    rm -f \$filename.sample" >> $NEWPATH/jobs/convert.sh
#  echo "  else" >> $NEWPATH/jobs/convert.sh
#  echo "    GS+=(\"\$filename\")" >> $NEWPATH/jobs/convert.sh
#  echo "  fi" >> $NEWPATH/jobs/convert.sh
#  echo "done" >> $NEWPATH/jobs/convert.sh
#  echo "a=$(join ' ' \"\${GS[\@]}\")" >> $NEWPATH/jobs/convert.sh
#  echo "cat \$a > $NEWPATH/export/data/data.gen" >> $NEWPATH/jobs/convert.sh
echo "for filename in $NEWPATH/export/data/*.fam; do" >> $NEWPATH/jobs/convert.sh
echo "  fbname=\$(basename \"\$filename\")" >> $NEWPATH/jobs/convert.sh
echo "  echo "Running \$fbname"" >> $NEWPATH/jobs/convert.sh
#  echo "  if [ ! -f $NEWPATH/export/data/data.sample ]; then" >> $NEWPATH/jobs/convert.sh
#  echo "    cp \$filename $NEWPATH/export/data/data.sample" >> $NEWPATH/jobs/convert.sh
#  echo "    cut -d ' ' -f 1-2 \$filename > $NEWPATH/export/data/data.sample.temp" >> $NEWPATH/jobs/convert.sh
#  echo "  else" >> $NEWPATH/jobs/convert.sh
#  echo "    cut -d ' ' -f 1-2 \$filename > \$filename.temp" >> $NEWPATH/jobs/convert.sh
#  echo "    diff=\$(diff $NEWPATH/export/data/data.sample.temp \$filename.temp)" >> $NEWPATH/jobs/convert.sh
#  echo "    if [ \"\$diff\" != '' ]; then" >> $NEWPATH/jobs/convert.sh
#  echo "      echo \"\$filename does not match, terminating\"" >> $NEWPATH/jobs/convert.sh
#  echo "      exit" >> $NEWPATH/jobs/convert.sh
#  echo "    else" >> $NEWPATH/jobs/convert.sh
#  echo "      echo \"\$filename matches\"" >> $NEWPATH/jobs/convert.sh
#  echo "      rm \$filename.temp" >> $NEWPATH/jobs/convert.sh
#  echo "    fi" >> $NEWPATH/jobs/convert.sh
#  echo "  fi" >> $NEWPATH/jobs/convert.sh
#  echo "done" >> $NEWPATH/jobs/convert.sh
#  echo "rm $NEWPATH/export/data/data.sample.temp" >> $NEWPATH/jobs/convert.sh
echo "  perl ~/swapIDs.pl $NEWPATH/export/data/\$fbname ~/collab_ids/cid$BNUM.csv ' '" >> $NEWPATH/jobs/convert.sh
#  perl swapIDs.pl B2478_17Dec2015/export/data/data.fam collab_ids/cidB2478.csv ' '
echo "done" >> $NEWPATH/jobs/convert.sh

# copy docs to export
cp -r $DATASETPATH/docs $NEWPATH/export

# change permissions
chmod 700 $NEWPATH/jobs/*

# declare complete
echo "SCRIPT COMPLETE"
