#!/bin/bash

set -euo pipefail

# Function to display debug messages
debug() {
    echo "[DEBUG] $1" >&2
}

# Function to display error messages and exit
error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Function to display progress
show_progress() {
    local current=$1
    local total=$2
    local percentage=$((current * 100 / total))
    printf "\rProgress: [%-50s] %d%%" "$(printf '=%.0s' $(seq 1 $((percentage / 2))))" "$percentage"
    if [ "$current" -eq "$total" ]; then
        echo  # New line after progress is complete
    fi
}

# Check for required tools
for tool in tesseract magick unpaper; do
    if ! command -v "$tool" &> /dev/null; then
        error "$tool is not installed. Please install it and try again."
    fi
done

# Ask for the folder containing images
echo "Please select the folder containing the textbook page images:"
mapfile -t folders < <(find . -maxdepth 1 -type d ! -path . -printf '%P\n' | sort)

if [ ${#folders[@]} -eq 0 ]; then
    error "No subdirectories found in the current directory."
fi

for i in "${!folders[@]}"; do
    echo "$((i+1)). ${folders[i]}"
done

read -rp "Enter the number of the folder: " folder_number

if ! [[ "$folder_number" =~ ^[0-9]+$ ]] || [ "$folder_number" -lt 1 ] || [ "$folder_number" -gt ${#folders[@]} ]; then
    error "Invalid selection."
fi

selected_folder="${folders[$((folder_number-1))]}"
debug "Selected folder: $selected_folder"

# Change to the selected directory
cd "$selected_folder" || error "Failed to change to directory: $selected_folder"
debug "Changed to directory: $(pwd)"

# Check if there are any image files in the directory
mapfile -t image_files < <(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" \) -printf '%P\n' | sort)

if [ ${#image_files[@]} -eq 0 ]; then
    error "No image files found in the selected directory."
fi

debug "Found ${#image_files[@]} image files"

# Create directories for intermediate steps
mkdir -p preprocessed dewarped

# Preprocess and OCR each image
total_files=${#image_files[@]}
for i in "${!image_files[@]}"; do
    img="${image_files[i]}"
    debug "Preprocessing $img"
    
    # Enhanced preprocessing
    magick "$img" -colorspace gray -normalize -sharpen 0x1 -despeckle -adaptive-threshold 10x10+5% "preprocessed/prep_$img"
    unpaper --dpi 300 --no-blackfilter --no-grayfilter --no-noisefilter --masks-cleararea 2 "preprocessed/prep_$img" "dewarped/dewarp_$img"
    
    debug "Processing dewarped_$img with Tesseract OCR"
    # Run Tesseract with pre-specified options
    tesseract "dewarped/dewarp_$img" "out$((i+1))" \
        -l eng \
        --oem 1 \
        --psm 3 \
        -c textord_min_linesize=2.5 \
        -c tessedit_char_whitelist="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\"#$%&'()*+,-./:;<=>?@[\\]^_\`{|}~ " \
        -c preserve_interword_spaces=1 \
        -c textord_tablefind_recognize_tables=1 \
        -c tessedit_pageseg_mode=1 \
        -c tessedit_do_invert=0
    
    show_progress $((i+1)) "$total_files"
done

debug "Tesseract OCR processing completed for all images."

# Combine all outputs into a single file
debug "Combining output files"
if ! cat out*.txt > combined_output.txt; then
    error "Failed to combine output files"
fi

debug "Output combined successfully into combined_output.txt."
echo "Processing completed successfully."

# Cleanup
rm -rf preprocessed dewarped
