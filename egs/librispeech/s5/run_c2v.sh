#!/usr/bin/env bash

data=$1

#lm_url=www.openslr.org/resources/11
mfccdir=mfcc
stage=8

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

#if [ $stage -le 1 ]; then
#  local/download_lm.sh $lm_url data/local/lm
#fi

if [ $stage -le 2 ]; then
  for part in $folderList; do
    local/data_prep.sh $data/$part data/"$(echo $part | sed s/-/_/g)"
  done
fi

# get folder lost with underscore

##
#if [ $stage -le 3 ]; then
#    local/prepare_dict.sh --stage 3 --nj 30 --cmd "$train_cmd" \
#      data/local/lm data/local/lm data/local/dict_nosp
#
#    utils/prepare_lang.sh data/local/dict_nosp \
#      "<UNK>" data/local/lang_tmp_nosp data/lang_nosp
#
#    local/format_lms.sh --src-dir data/lang_nosp data/local/lm
#fi


#if [ $stage -le 4 ]; then
#  # Create ConstArpaLm format language model for full 3-gram and 4-gram LMs
#  utils/build_const_arpa_lm.sh data/local/lm/lm_tglarge.arpa.gz \
#    data/lang_nosp data/lang_nosp_test_tglarge
#  utils/build_const_arpa_lm.sh data/local/lm/lm_fglarge.arpa.gz \
#    data/lang_nosp data/lang_nosp_test_fglarge
#fi

if [ $stage -le 6 ]; then
  for part in $folderList; do
    steps/make_mfcc.sh --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" --nj 40 data/"$(echo $part | sed s/-/_/g)" exp/make_mfcc/"$(echo $part | sed s/-/_/g)" $mfccdir
    steps/compute_cmvn_stats.sh data/"$(echo $part | sed s/-/_/g)" exp/make_mfcc/"$(echo $part | sed s/-/_/g)" $mfccdir
    utils/fix_data_dir.sh $mfccdir
  done
fi


if [ $stage -le 7 ]; then
  for part in $folderList; do
#    extract ivectors
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 40 \
      data/"$(echo $part | sed s/-/_/g)" exp/nnet3_cleaned/extractor exp/nnet3_cleaned/ivectors_"$(echo $part | sed s/-/_/g)"
  done
fi

dir=exp/chain_cleaned/tdnn_1d_sp
graph_dir=$dir/graph_tgsmall/

if [ $stage -le 8 ]; then
  utils/mkgraph.sh --self-loop-scale 1.0 --remove-oov \
      data/lang_test_tgsmall $dir $graph_dir
fi

if [ $stage -le 9 ]; then
# decode
  for part in $folderList; do
    steps/nnet3/decode.sh --cmd "$decode_cmd" --nj 40 \
    --online-ivector-dir exp/nnet3_cleaned/ivectors_"$(echo $part | sed s/-/_/g)"
      $graph_dir data/"$(echo $part | sed s/-/_/g)" $dir/decode_tgsmall_"$(echo $part | sed s/-/_/g)"
  done
fi

