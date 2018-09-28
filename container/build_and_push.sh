#!/usr/bin/env bash

AWS_PROFILE=""
CWD=$(cd "$(dirname "$0")"; pwd)
ROOT_DIR=$(dirname "$CWD")
DATA_DIR=$ROOT_DIR/data

function assert_command() {
  local cmd="$1"
  local message="$2"
  local retval=$(eval "$cmd")
  if [ $? -ne 0 ]; then
    echo $message
    exit 1
  fi
  echo "$retval"
}

function prepare_data() {
  local train_dir=$DATA_DIR/prepared_data/data/train
  local test_dir=$DATA_DIR/prepared_data/data/test
  local validation_dir=$DATA_DIR/prepared_data/data/validation

  if [ -d $train_dir ] && [ -d $test_dir ] && [ -d $validation_dir ]; then
    local recreate
    read -p "It looks like the data has already been prepared. Do you want to redo it? (y/n) " recreate
    [ "$recreate" != "y" ] && return
  fi

  local data_file=$DATA_DIR/kaggle_dogs_cats.zip

  if [ ! -f $data_file ]; then
    echo "Please download Kaggle dogs & cats data file and put in under $data_file"
    exit 1
  fi

  [ -d /tmp/kaggle_dogs_cats ] && rm -rf /tmp/kaggle_dogs_cats

  echo "Unzipping data"
  unzip $data_file -d /tmp/kaggle_dogs_cats 
  cd /tmp/kaggle_dogs_cats
  unzip train.zip
  cd train

  [ -d $DATA_DIR/prepared_data ] && rm -rf $DATA_DIR/prepared_data

  local train_dir=$DATA_DIR/prepared_data/data/train
  local test_dir=$DATA_DIR/prepared_data/data/test
  local validation_dir=$DATA_DIR/prepared_data/data/validation

  mkdir -p $train_dir/cat 
  mkdir -p $train_dir/dog
  mkdir -p $test_dir/cat 
  mkdir -p $test_dir/dog
  mkdir -p $validation_dir/cat
  mkdir -p $validation_dir/dog

  local train_samples_per_class=1000
  local test_samples_per_class=500
  local valid_samples_per_class=500

  echo "Copying $train_samples_per_class cat & dog images to $train_dir"
  for ((i=0; i < train_samples_per_class; i++)); do
    cp cat.${i}.jpg $train_dir/cat
    cp dog.${i}.jpg $train_dir/dog
  done

  echo "Copying $test_samples_per_class cat & dog images to $test_dir"
  for ((i=train_samples_per_class; i < train_samples_per_class + test_samples_per_class; i++)); do
    cp cat.${i}.jpg $test_dir/cat
    cp dog.${i}.jpg $test_dir/dog
  done

  echo "Copying $valid_samples_per_class cat & dog images to $validation_dir"
  for ((i=train_samples_per_class + test_samples_per_class; i < train_samples_per_class + test_samples_per_class + valid_samples_per_class; i++)); do
    cp cat.${i}.jpg $validation_dir/cat
    cp dog.${i}.jpg $validation_dir/dog
  done

  rm -rf /tmp/kaggle_dogs_cats
}

function get_account_number() {
  local account_number=$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE)
  if [ $? -ne 0 ]; then
    echo "Failed getting account number"
    exit 1
  fi
  echo $account_number
}

function upload_data() {
  local account_number=$(get_account_number)
  local region=$(aws configure get region)
  region=${region:-eu-west-1}
  local s3_bucket="sagemaker-${region}-${account_number}"

  aws s3 ls s3://${s3_bucket} &> /dev/null
  if [ $? -ne 0 ]; then
    assert_command "aws s3 mb s3://${s3_bucket} --profile $AWS_PROFILE" "Failed to create s3 bucket"
  fi

  local prefix=$1
  aws s3 ls s3://${s3_bucket}/${prefix} &> /dev/null
  if [ $? -eq 0 ]; then
    read -p "Looks like data has already been uploaded. Do you want to reupload? (y/n)" answer
    [ "$answer" != "y" ] && return
  fi

  echo "Uploading data to s3://${s3_bucket}/${prefix}"
  aws s3 sync $DATA_DIR/prepared_data/data s3://${s3_bucket}/${prefix}/data --profile $AWS_PROFILE
}

function build_and_push() {
  local image=$1
  local account_number=$(get_account_number)
  local region=$(aws configure get region)
  region=${region:-eu-west-1}
  local image_name="${account_number}.dkr.ecr.${region}.amazonaws.com/${image}:latest"

  aws ecr describe-repositories --repository-names "${image}" --profile $AWS_PROFILE &> /dev/null

  if [ $? -ne 0 ]; then
    echo "Creating repository $image"
    assert_command "aws ecr create-repository --repository-name $image --profile $AWS_PROFILE > /dev/null" "Failed to create repository"
  fi

  echo "Build and push docker image"
  $(aws ecr get-login --region ${region} --no-include-email --profile $AWS_PROFILE)

  cd $CWD
  chmod +x cnn/train
  chmod +x cnn/serve

  docker build -t $image .
  docker tag $image $image_name
  docker push $image_name

  untagged_images=$(aws ecr list-images --region $region --repository-name $image --filter "tagStatus=UNTAGGED" --query 'imageIds[*]' --output json)
  echo "Untagged images to be deleted: $untagged_images"
  aws ecr batch-delete-image --region $region --repository-name $image --image-ids "$untagged_images" || true
}

function get_config() {
  local config_name=$1
  echo `python -c "import sys; sys.path.append('$ROOT_DIR'); import config as conf; print(conf.${config_name})" 2>/dev/null`
}

AWS_PROFILE=$(get_config AWS_PROFILE)
IMAGE_BASE_NAME=$(get_config IMAGE_BASE_NAME)
S3_BUCKET_PREFIX=$(get_config S3_BUCKET_PREFIX)

OPS=""
[ $# -ge 1 ] && OPS=$1

case "$OPS" in
  prepare)
    prepare_data
    ;;

  upload)
    upload_data $S3_BUCKET_PREFIX
    ;;

  push)
    build_and_push $IMAGE_BASE_NAME
    ;;

  *)
    prepare_data
    upload_data $S3_BUCKET_PREFIX
    build_and_push $IMAGE_BASE_NAME
    ;;
esac
