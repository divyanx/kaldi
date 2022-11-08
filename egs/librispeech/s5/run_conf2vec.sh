#!/usr/bin/env bash

data=$1 #It accepts the path of data as first arg
echo the data path is: $data
#lm_url=www.openslr.org/resources/11
stage=0

# read folder names inside the data folder
folders_paths=$(ls -d $data/*/)

# create an array of folder names
folders=()
for folder_path in $folders_paths; do
    folder=$(basename $folder_path)
    folders+=("$folder")
done

echo -----------------------------------
echo Working on the following folders:
folderList="${folders[*]}"
echo $folderList
echo -----------------------------------

. ./cmd.sh
. ./path.sh


# get a foldername in which - is replaced with _
folders_underscore=()
for folder in $folderList; do
    folder_underscore=$(echo $folder | sed s/-/_/g)
    folders_underscore+=("$folder_underscore")
done

folderList_underscore="${folders_underscore[*]}"

if [ $stage -le 0 ]; then
  echo within stage 0
  #wget http://kaldi-asr.org/models/13/0013_librispeech_v1_chain.tar.gz
  #wget http://kaldi-asr.org/models/13/0013_librispeech_v1_extractor.tar.gz
  #wget http://kaldi-asr.org/models/13/0013_librispeech_v1_lm.tar.gz

  tar -xvzf 0013_librispeech_v1_chain.tar.gz
  tar -xvzf 0013_librispeech_v1_extractor.tar.gz
  tar -xvzf 0013_librispeech_v1_lm.tar.gz
fi

echo  stage 0 complete

if [ $stage -le 1 ]; then
   echo within stage 1
  for part in $folderList; do
    local/data_prep.sh "$data/$part" data/"$(echo $part | sed s/-/_/g)"
  done
fi
echo  stage 1 complete
if [ $stage -le 2 ]; then
   echo within stage 2
  for datadir in $folderList_underscore;
  do
      utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
  done
fi

echo  stage 2 complete
if [ $stage -le 3 ]; then
   echo within stage 3

  for datadir in $folderList_underscore; do
      steps/make_mfcc.sh --nj 20 --mfcc-config conf/mfcc_hires.conf \
        --cmd "$train_cmd" data/${datadir}_hires
      steps/compute_cmvn_stats.sh data/${datadir}_hires
      utils/fix_data_dir.sh data/${datadir}_hires
  done
fi
echo  stage 3 complete
if [ $stage -le 4 ]; then
   echo within stage 4
  for data in  $folderList_underscore; do
      nspk=$(wc -l <data/${data}_hires/spk2utt)
      echo ---------------------$data---------------------
      steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nspk  \
        data/${data}_hires exp/nnet3_cleaned/extractor \
        exp/nnet3_cleaned/ivectors_${data}_hires
    done
fi
echo  stage 4 complete
dir=exp/chain_cleaned/tdnn_1d_sp
graph_dir=$dir/graph_tgsmall

if [ $stage -le 5 ]; then
   echo within stage 5
  utils/mkgraph.sh --self-loop-scale 1.0 --remove-oov \
    data/lang_test_tgsmall $dir $graph_dir
fi

echo  stage 5 complete
if [ $stage -le 6 ]; then
   echo within stage 6
  for decode_set in $folderList_underscore; do
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --nj 8 --cmd "$decode_cmd" \
      --online-ivector-dir exp/nnet3_cleaned/ivectors_${decode_set}_hires \
      $graph_dir data/${decode_set}_hires $dir/decode_${decode_set}_tgsmall
  done
fi
echo  stage 6 complete
# create sausages from the decoded lattice
sausages_dir=$dir/sausages
if [ $stage -le 7 ]; then
   echo within stage 7
  for decode_set in $folderList_underscore; do
    mkdir -p $sausages_dir/$decode_set
#    iterate all lattice file in the decode folder
    curr_dir=$dir/decode_${decode_set}_tgsmall

#     create a list of all files in the dir with format lat.*.gz
     lats=$(ls $curr_dir/lat.*.gz)
     for lat in $lats; do
  #    get the file name without the path
       filename=$(basename $lat)
           # get file number\
       file_num=$(echo $filename | cut -d'.' -f2)
  #    create a sausage file name with the same number
       sausage_file=$sausages_dir/$decode_set/sausage.$file_num.sau
       lattice-mbr-decode --acoustic-scale=0.1 \
         "ark:gunzip -c $lat|" 'ark,t:|utils/int2sym.pl -f 2- data/lang_test_tgsmall/words.txt > text' ark:/dev/null ark,t:$sausage_file
     done
  done
fi
echo  stage 7 complete
if [ $stage -le 8 ]; then
   echo within stage 8
  touch $sausages_dir/all_sausages.sau
#   merge all sausages into all file
  for decode_set in $folderList_underscore; do
    curr_dir=$sausages_dir/$decode_set
    sausages=$(ls $curr_dir/sausage.*.sau)
    for sausage in $sausages; do
      cat $sausage >> $sausages_dir/all_sausages.sau
    done
  done
fi
echo  stage 8 complete
#update the path of conf2vec folder cloned from github url = https://github.com/divyanx/confusion2vec_2.0
conf2vec_root="/Users/divyansh/Research-Internship-Large-Files/confusion2vec_2.0"

#concat name of all folders in a single string seperated by _
folderList_underscore_name=$(echo $folderList_underscore | sed s/\ /__/g)
if [ $stage -le 9 ]; then
   echo within stage 9
  echo "entering stage 9 "
  python3 $conf2vec_root/scripts/convert_sausage.py $sausages_dir/all_sausages.sau data/lang_test_tgsmall/words.txt $conf2vec_root/data/"$folderList_underscore_name".sau
fi
echo  stage 9 complete
if [ $stage -le 10 ]; then
   echo within stage 10
  echo "entering stage 10 "
  mkdir -p $conf2vec_root/vectors/$folderList_underscore_name
  echo " folders created successfully"
  $conf2vec_root/c2v_fasttext c2v-inter -t 0.001 -neg 64 -ws 5 -epoch 5 -input $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/inter-confusion -thread 32 -dim 300 -lr 0.01
  $conf2vec_root/c2v_fasttext c2v-intra -t 0.001 -neg 64 -ws 5 -epoch 5 -input  $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/intra-confusion -thread 32 -dim 300 -lr 0.01
  $conf2vec_root/c2v_fasttext c2v-top -t 0.001 -neg 64 -ws 5 -epoch 5 -input  $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/top-confusion -thread 32 -dim 300 -lr 0.01
  $conf2vec_root/c2v_fasttext c2v-hybrid -t 0.001 -neg 64 -ws 5 -epoch 5 -input  $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/hybrid-confusion -thread 32 -dim 300 -lr 0.01

fi

echo  stage 10 complete
# input_model_path=wiki.en.bin
input_model_path=/Users/divyansh/gensim-data/word2vec-google-news-300/word2vec-google-news-300

if [ $stage -le 11 ]; then
  echo "entering stage 11 "
  $conf2vec_root/c2v_fasttext c2v-inter -t 0.001 -neg 64 -ws 5 -epoch 5 -input $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/inter-confusion-pre-wiki -thread 32 -dim 300 -lr 0.01 -inputModel "$input_model_path" -incr
  $conf2vec_root/c2v_fasttext c2v-intra -t 0.001 -neg 64 -ws 5 -epoch 5 -input  $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/intra-confusion-pre-wiki -thread 32 -dim 300 -lr 0.01 -inputModel "$input_model_path" -incr
  $conf2vec_root/c2v_fasttext c2v-top -t 0.001 -neg 64 -ws 5 -epoch 5 -input  $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/top-confusion-pre-wiki -thread 32 -dim 300 -lr 0.01 -inputModel "$input_model_path" -incr
  $conf2vec_root/c2v_fasttext c2v-hybrid -t 0.001 -neg 64 -ws 5 -epoch 5 -input  $conf2vec_root/data/$folderList_underscore_name.sau -output $conf2vec_root/vectors/$folderList_underscore_name/hybrid-confusion-pre-wiki -thread 32 -dim 300 -lr 0.01 -inputModel "$input_model_path" -incr

fi

echo  stage 11 complete