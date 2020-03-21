#!/bin/bash
# command examples:

#  ./s3_tool.sh set_acl_from_file  --acl 'private' --key_file 's3__.log'
#   set acl (private) for each line from file   s3__.log

# ./s3_tool.sh set_acl_buckets --buckets 'bucket_name1 bucket_name2' --acl 'private'
# set acl for buckets

# ./s3_tool.sh set_acl_prefix --buckets 'bucket_name' --prefix 'demo' --acl 'public-read-write'
# set acl for bucket and prefix

# ./s3_tool.sh scan_buckets --buckets 'bucket_name1 bucket_name2'
# scan buckets

# ./s3_tool.sh  scan_prefix --buckets 'bucket_name1' --prefix 'prefix'
# scan bucket with prefix

# ./s3_tool.sh scan_via_tag
# scan bucket  via tag

# ./s3_tool.sh  get_s3_tag  --tag_for_scan  'scan'
# get s3 bucket with tag

#  ./s3_tool.sh copy_to_bucket --key_file file_name  --new_bucket bucket_name
# copy objects  keys from file to new_bucket

# ./s3_tool.sh get_keys_bucket_prefix --key_file test_keys --buckets bucket_name --prefix prefix_name
# get keys list from bucket and prefix

# ./s3_tool.sh get_keys_bucket --key_file test_keys --buckets bucket_name
# get keys list from bucket and prefix

#./s3_tool.sh check_keys_file --source_file /tmp/product_photo2.txt --bucket_file test_keys --dif_file diff_file
# find  each key from source_file and find it in  bucket_file   . if key not exist add it to dif_file


# flags :
# --acl
     #private
     #public-read
     #public-read-write
     #authenticated-read
     #aws-exec-read
     #bucket-owner-read
     #bucket-owner-full-control
# --tag_for_scan  - s3 tag for scan
# --log_prefix    - prefix for log file
# --buckets  - s3 buckets names
# --prefix  s3 bucket prefix
# --aws_profile  - aws profile  from  ~/.credentials  = default
# --search_term  -  search  word for acl   =  AllUsers
# --key_file   - file name for command  set_acl_from_file




command=$1
declare -i max_paralel_proces=21
declare -i delay_after=20
declare -i send_keys=0
max_items=400
wait_sleep=1
start_time=$(date +%F:%H:%M:%S)
aws_profile="default"
tag_for_scan="scan"
search_term="AllUsers"

#function_________________________
function get_s3_buckets {
 local bucket_for_scan=$( aws s3 ls --profile $aws_profile  |cut -f3 -d' ')
 local bucket_for_scan_tag=''
 for bucket in $bucket_for_scan
  do
   tags=$(aws s3api get-bucket-tagging --bucket $bucket --profile $aws_profile  2>$log_error)
   result_found=$(echo $tags |  jq -r '.TagSet[].Key' | grep  "$tag_for_scan")
   if [ ! -z "$result_found" ] ; then
      bucket_for_scan_tag+="${bucket} "
   fi
  done
 echo "$bucket_for_scan_tag"
}


function check_key {
 json=$(aws s3api get-object-acl --bucket $1 --key $2 --profile $aws_profile 2>$log_error)
 result_found=$(echo $json | jq -r '.Grants[].Grantee[]' | grep  "$search_term")
     if [ ! -z "$result_found" ]; then
        last_modified=$(aws s3 ls "$1/$2" --profile $aws_profile 2>$log_error  | cut -f1 -d' ')
        echo "$1/$2 $last_modified">>$log;
        echo "$1/$2">>$log_acl;
        echo "$json" >> $log_acl
        echo '****************' >> $log_acl
        echo "$1/$2 ---  public -- $last_modified"
     fi
}

function set_acl_buckets {
 #1 -acl
 aws s3api  put-object-acl  --bucket "$2" --key "$3" --acl $1 --profile $aws_profile 2>> $log_error  1>>$log

}

function s3_cp {
#1 line
#2 new_bucket

 from="s3://$1"
 old_bucket=$(echo $1 | cut -f1 -d'/')
 to="s3://$(echo $1 | sed -e 's/'$old_bucket'/'$2'/'g)"
 aws s3 cp $from  $to --acl public-read 2>> $log_error  1>>$log


}

function check_keys_file  {
#1 source_file
#2 bucket_file
#3 dif_file
rm -f $3
declare -i line=1
all_line=$(wc -l $1)
echo " source_file =$1 bucket_file=$2  dif_file=$3  "
while IFS= read -r LINE || [ -n "$LINE" ];
 do
  bucket=$(echo $LINE | cut -f1 -d'/' )
  key=$(echo $LINE |cut -f1 -d' ' | sed -e 's/'$bucket'\///'g )
  result=$(grep  "$key" $2)
  if [ -z "$result" ];
   then
    echo $key>>$3

    fi
  echo " line $line of $all_line "
  line+=1
 done <$1

}


function get_keys_bucket {
#1 bucket
#2 prefix
#3 file
echo "***** $(date +%F:%H:%M:%S)  === backet =====  start_time=$start_time "  | tee -a $log_app
echo "$1" | tee -a $log_app
echo "***** $(date +%F:%H:%M:%S)  prefix  : $(echo $2 | cut -f2 -d ' ') " | tee -a $log_app

bucket=$1

rm -f $3
nexttoken='init'
declare -i all_keys=0
while [ -n "$nexttoken" ]
 do
  case $nexttoken in
   init)
    json=$(aws s3api list-objects-v2     --bucket $bucket --profile $aws_profile --max-items $max_items $2 )
    ;;
   *)
   json=$(aws s3api list-objects-v2     --bucket $bucket --profile $aws_profile --max-items $max_items $2 --starting-token $nexttoken )
   ;;
  esac
 echo $json |jq -r '.Contents[].Key' >>$3
 nexttoken=$(echo $json |jq -r '.NextToken')
 all_keys+=$max_items
 echo "**** get $all_keys  keys"
 if [[ "$nexttoken" == "null" ]] ; then
  nexttoken=''
  echo "nexttoken  null"
 fi
# awk '{print "s3_bucket_name/"$0}' $3
# echo "keys =  $(wc -l)"
done


}

function command_buckets {
#1 -buckets
   echo "***** $(date +%F:%H:%M:%S)  === backets =====  start_time=$start_time "  | tee -a $log_app
   echo "$1" | tee -a $log_app
   echo "***** $(date +%F:%H:%M:%S)  bucket amount : $(echo $1 | wc 	--words )" | tee -a $log_app
   echo "***** $(date +%F:%H:%M:%S)  prefix  : $(echo $2 | cut -f2 -d ' ') " | tee -a $log_app
   echo "***** $(date +%F:%H:%M:%S)  command = $3  "   | tee -a $log_app
  for bucket in $1 ; do
          declare -i send_backet_keys=0
          echo "***** $(date +%F:%H:%M:%S) $3  backet $bucket start_time=$start_time " | tee -a $log_app
          nexttoken='init'
          declare -i all_keys=0
          while [ -n "$nexttoken" ]
           do
            case $nexttoken in
             init)
              json=$(aws s3api list-objects-v2     --bucket $bucket --profile $aws_profile --max-items $max_items $2 )
              ;;
             *)
             json=$(aws s3api list-objects-v2     --bucket $bucket --profile $aws_profile --max-items $max_items $2 --starting-token $nexttoken )
             ;;
            esac
            keys_for_scan=$(echo $json |jq -r '.Contents[].Key')
            nexttoken=$(echo $json |jq -r '.NextToken')
            if [[ "$nexttoken" == "null" ]] ; then
             nexttoken=''
             echo "nexttoken  null"
            fi
            for key in $keys_for_scan ; do
               declare -i paralel_proces=0
               paralel_proces+=$(ps aux | grep aws  | wc -l)
               while [[ $max_paralel_proces -lt $paralel_proces ]]
                do
                 echo "***** $(date +%F:%H:%M:%S) sleep  paralel_proces = $paralel_proces  max_paralel_proces=$max_paralel_proces  start_time=$start_time  " | tee -a $log_app
                 sleep 1
                 declare -i paralel_proces=0
                 paralel_proces+=$(ps aux | grep aws  | wc -l)
                done
#                echo "$bucket/$key"
               $3 "$bucket"  "$key" &
               send_keys+=1
               send_backet_keys+=1
               all_keys+=1
               if [[ ! "$send_keys" -lt "$delay_after" ]] ; then
                 echo "***** $(date +%F:%H:%M:%S) send $send_keys keys  wait_sleep $wait_sleep  bucket=$bucket  send_backet_keys=$send_backet_keys  all_keys=$all_keys start_time=$start_time" | tee -a $log_app
                 sleep $wait_sleep
                 declare -i send_keys=0
               fi
            done
           done
          echo  "***** $(date +%F:%H:%M:%S) done   backet $bucket send_backet_keys=$send_backet_keys  start_time=$start_time " | tee -a $log_app
   done
  echo  "***** $(date +%F:%H:%M:%S) done   all_keys=$all_keys start_time=$start_time  " | tee -a $log_app
}

#------ main -------
while [[ $# > 0 ]]; do
    key="$1"
    case "$key" in
      --log_prefix)
         log_prefix="$2"
         shift
      ;;
      --buckets)
         buckets="$2"
         shift
      ;;
      --prefix)
         prefix="$2"
         shift
      ;;
      --aws_profile)
         aws_profile="$2"
         shift
      ;;
      --tag_for_scan)
         tag_for_scan="$2"
         shift
      ;;

      --search_term)
         search_term="$2"
         shift
      ;;
      --acl)
         acl="$2"
         shift
      ;;
      --new_bucket)
         new_bucket="$2"
         shift
      ;;
      --key_file)
         key_file="$2"
         shift
      ;;
      --split_number)
         split_number="$2"
         shift
      ;;
      --split_prefix)
         split_prefix="$2"
         shift
      ;;
      --source_file)
         source_file="$2"
         shift
      ;;
      --bucket_file)
         bucket_file="$2"
         shift
      ;;
      --dif_file)
         dif_file="$2"
         shift
      ;;

       *)
        ;;
    esac
    shift
  done

# set variables
log="s3_$log_prefix""_.log"
log_acl="s3_$log_prefix""_acl.log"
log_error="s3_$log_prefix""_error.log"
log_app="s3_$log_prefix""_app.log"






case $command in
  scan_via_tag)
         rm -f $log $log_acl $log_acl $log_error  $log_app
         echo "*****  scan_via_tag  *******"
         echo "***** $(date +%F:%H:%M:%S)   get buckets for scan  start_time=$start_time " | tee -a $log_app
         bucket_for_scan_tag="$(get_s3_buckets)"
         command_buckets "$bucket_for_scan_tag"  '' 'check_key'

  ;;
  scan_buckets)
         rm -f $log $log_acl $log_acl $log_error  $log_app
         command_buckets "$buckets" '' 'check_key'
  ;;

  scan_prefix)
         rm -f $log $log_acl $log_acl $log_error  $log_app
         command_buckets "$buckets" "--prefix $prefix" "check_key"
  ;;

  set_acl_buckets)
       command_buckets "$buckets" "" "set_acl_buckets $acl "
  ;;

  set_acl_prefix)
       command_buckets "$buckets" "--prefix $prefix" "set_acl_buckets $acl "
  ;;


 set_acl_from_file)
         declare -i all_keys=0
         echo "***** $(date +%F:%H:%M:%S)   set_acl_from_file  start_time=$start_time " | tee -a $log_app
         while IFS= read -r LINE || [ -n "$LINE" ];
         do
          bucket=$(echo $LINE | cut -f1 -d'/' )
          key=$(echo $LINE |cut -f1 -d' ' | sed -e 's/'$bucket'\///'g )
          echo "bucket $bucket    key =$key   acl=$acl"
          declare -i paralel_proces=0
          paralel_proces+=$(ps aux | grep aws  | wc -l)
          while [[ $max_paralel_proces -lt $paralel_proces ]]
           do
            echo "***** $(date +%F:%H:%M:%S) sleep  paralel_proces = $paralel_proces  max_paralel_proces=$max_paralel_proces  start_time=$start_time  " | tee -a $log_app
            sleep 1
            declare -i paralel_proces=0
            paralel_proces+=$(ps aux | grep aws  | wc -l)
           done
           set_acl_buckets "$acl" "$bucket"  "$key" &
           send_keys+=1
           all_keys+=1
           if [[ ! "$send_keys" -lt "$delay_after" ]] ; then
             echo "***** $(date +%F:%H:%M:%S) send $send_keys keys  wait_sleep $wait_sleep  bucket=$bucket   all_keys=$all_keys start_time=$start_time" | tee -a $log_app
             sleep $wait_sleep
             declare -i send_keys=0
           fi

         done < $key_file
 ;;

  get_s3_tag)
         s3=$(get_s3_buckets)
         echo $s3
  ;;

  get_keys_bucket_prefix)
         echo "get_keys_bucket $buckets   . save to file $key_file"
         get_keys_bucket $buckets "--prefix $prefix" $key_file

  ;;
  get_keys_bucket)
         echo "get_keys_bucket $buckets   . save to file $key_file"
         get_keys_bucket $buckets "" $key_file

  ;;


  check_keys_file)
    check_keys_file $source_file  $bucket_file $dif_file
  ;;

  copy_to_bucket)
        keys_to_copy=$(wc -l $key_file)
        echo "$key_file has $keys_to_copy keys to copy  "
        declare -i all_keys=0
         echo "***** $(date +%F:%H:%M:%S) $key_file   copy to new bucket  start_time=$start_time " | tee -a $log_app
         while IFS= read -r LINE || [ -n "$LINE" ];
         do
 #         echo "bucket $new_bucket    $LINE"
          declare -i paralel_proces=0
          paralel_proces+=$(ps aux | grep aws  | wc -l)
          while [[ $max_paralel_proces -lt $paralel_proces ]]
           do
            echo "***** $(date +%F:%H:%M:%S)  $key_file sleep  paralel_proces = $paralel_proces  max_paralel_proces=$max_paralel_proces  start_time=$start_time  " | tee -a $log_app
            sleep 1
            declare -i paralel_proces=0
            paralel_proces+=$(ps aux | grep aws  | wc -l)
           done
          s3_cp "$LINE"  "$new_bucket" &
           send_keys+=1
           all_keys+=1
           if [[ ! "$send_keys" -lt "$delay_after" ]] ; then
             echo "***** $(date +%F:%H:%M:%S) $key_file send $all_keys keys of $keys_to_copy  wait_sleep $wait_sleep   start_time=$start_time" | tee -a $log_app
             sleep $wait_sleep
             declare -i send_keys=0
           fi

         done < $key_file
    echo "***** $key_file    done  "
    echo "***** $key_file    done  "  >/var/log/s3_log

  ;;
  split_file)
    declare -i file_line=0
    declare -i file_line_count=$(wc -l $key_file  | cut -d' ' -f1)
    declare -i max_file_line=$((file_line_count/$split_number))
    echo "file_line_count=$file_line_count"
    echo "max_file_line=$max_file_line"
    declare -i file_posfix=0
    while IFS= read -r LINE || [ -n "$LINE" ];
      do
       if [[ "$file_line" -ge "$max_file_line" ]] ; then
         file_posfix+=1
         declare -i file_line=0
         echo "file_posfix=$file_posfix"
       fi
       current_file_name=$split_prefix"_"$file_posfix

       echo "$LINE">> $current_file_name
       file_line+=1
      done < $key_file
  ;;

  *)
         echo "***** none command"
  ;;

esac