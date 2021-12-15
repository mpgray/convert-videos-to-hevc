#!/bin/bash
# convert video types to hevc recursively
# By Michael Gray
#####################################
if [ -z $1 ];then echo Give target directory; exit 0;fi
find "$1" -depth \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.mpg" -o -iname "*.mov" -o -iname "*.avi"  -o -iname "*.iso" -o -iname "*.mpeg" \) -a -not -iname "*HEVC.mkv" |  while read file ; do
directory=$(dirname "$file")
oldfilename=$(basename "$file")
newfilename=$(basename "${file%.*}")
nice -n 15 ffmpeg -threads 4 -i "$directory/$oldfilename" -vaapi_device /dev/dri/renderD128 -vcodec hevc_vaapi -vf format='nv12|vaapi,hwupload' -qp:v 20 -c:a libvorbis -qscale  5 -ac 6 -f matroska "$directory/$newfilename - HEVC.mkv" </dev/null
# rm "$directory/$oldfilename"
done
