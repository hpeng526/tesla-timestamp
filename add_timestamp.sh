#!/bin/bash

# 检查是否提供了目录参数
if [ -z "$1" ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# 安装必要的工具 (已移除reverse-geocoder检查)
if ! command -v ffmpeg &> /dev/null; then
    echo "ffmpeg is required but not installed. Installing..."
    brew install ffmpeg
fi

if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Installing..."
    brew install jq
fi

# 处理目录
process_directory() {
    local dir="$1"
    # local event_file="$dir/event.json"
    
    # # 获取位置信息 (显示详细地址+经纬度)
    # local location=""
    # if [ -f "$event_file" ]; then
    #     local lat=$(jq -r '.est_lat' "$event_file")
    #     local lon=$(jq -r '.est_lon' "$event_file")
        
    #     if [ "$lat" != "null" ] && [ "$lon" != "null" ]; then
    #         # 获取完整详细地址
    #         location=$(curl -s --max-time 5 --retry 2 "https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon" | 
    #                   jq -r '.display_name' | tr -d '\n')
            
    #         if [ -z "$location" ]; then
    #             location=$(printf "位置: %.4f°N, %.4f°E" $lat $lon)
    #         else
    #             # 保留完整地址并添加经纬度
    #             location="${location} (${lat}, ${lon})"
    #         fi
    #         echo "获取到位置信息: $location"
    #     else
    #         location="位置信息不可用"
    #     fi
    # else
    #     location="无event.json文件"
    # fi

    # 处理视频文件
    for video in "$dir"/*.mp4; do
        # 从文件名中提取时间
        local filename=$(basename "$video")
        if [[ "$filename" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2}) ]]; then
            local date="${BASH_REMATCH[1]}"
            local hour="${BASH_REMATCH[2]}"
            local minute="${BASH_REMATCH[3]}"
            local second="${BASH_REMATCH[4]}"
            
            # 输出文件路径
            local output="${video%.*}_timestamped.mp4"
            
            # 添加时间水印和位置信息(启用GPU加速)
            # 优化画质参数(保持GPU加速)
            # 这部分明确使用了h264_videotoolbox
            # 使用GPU加速处理
            # ffmpeg -hwaccel videotoolbox -i "$video" \
            #     -vf "drawtext=fontfile=/System/Library/Fonts/PingFang.ttc:font=PingFang SC: \
            #         text='%{pts\:localtime\:$(date -j -f "%Y-%m-%d %H:%M:%S" "$date $hour:$minute:$second" +%s)}': \
            #         x=10: y=10: fontsize=24: fontcolor=white: box=1: boxcolor=black@0.5, \
            #         drawtext=fontfile=/System/Library/Fonts/PingFang.ttc:font=PingFang SC: \
            #         text='${location:-位置信息获取失败}': \
            #         x=10: y=40: fontsize=24: fontcolor=white: box=1: boxcolor=black@0.5" \
            #     -c:v h264_videotoolbox -b:v 5000k -maxrate 8000k -bufsize 8000k \
            #     -profile:v main -pix_fmt yuv420p -color_range mpeg \
            #     -movflags +faststart -c:a copy \
            #     "$output"
             ffmpeg -hwaccel videotoolbox -i "$video" \
                -vf "drawtext=fontfile=/System/Library/Fonts/PingFang.ttc:font=PingFang SC: \
                    text='%{pts\:localtime\:$(date -j -f "%Y-%m-%d %H:%M:%S" "$date $hour:$minute:$second" +%s)}': \
                    x=10: y=10: fontsize=50: fontcolor=white: box=1: boxcolor=black@0.5" \
                -c:v h264_videotoolbox -b:v 5000k -maxrate 8000k -bufsize 8000k \
                -profile:v main -pix_fmt yuv420p -color_range mpeg \
                -movflags +faststart -c:a copy \
                "$output"
            
            echo "Processed: $output"
        fi
    done
}

# 主循环
find "$1" -type d -name "20*-*-*_*-*-*" | while read -r dir; do
    process_directory "$dir"
done

echo "All videos processed."
