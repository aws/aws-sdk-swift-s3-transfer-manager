#!/bin/bash

# Create test dataset with nested subfolders and large files
# GitHub Actions compatible version

# Use $HOME for local development, temp directory for GitHub Actions
if [ "$GITHUB_ACTIONS" = "true" ]; then
    BASE_DIR="${TMPDIR:-/tmp}/test_dataset"
else
    BASE_DIR="$HOME/test_dataset"
fi

# GitHub Actions parameters target 500MB total, local can be larger
# GitHub Actions test dataset calculation:
#   Num folders: 2 * (1 + 2 + 4) = 14 directories
#   Num files: 14 directories * 5 files = 70 files
#   Total size: 70 files * (3MB + 4MB)/2 = 245MB avg
# Local test dataset calculation:
#   Num folders: 3 * (1 + 2 + 4) = 21 directories
#   Num files: 21 directories * 15 files = 315 files
#   Total size: 315 files * (12MB + 18MB)/2 = 4.7GB avg
if [ "$GITHUB_ACTIONS" = "true" ]; then
    TOP_FOLDERS=2
    NESTED_LEVELS=3
    FILES_PER_FOLDER=5
    MIN_SIZE_MB=3
    MAX_SIZE_MB=4
else
    TOP_FOLDERS=3
    NESTED_LEVELS=3
    FILES_PER_FOLDER=15
    MIN_SIZE_MB=12
    MAX_SIZE_MB=18
fi

echo "Creating test dataset at $BASE_DIR..."
echo "GitHub Actions mode: ${GITHUB_ACTIONS:-false}"
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"

create_files() {
    local dir="$1"
    local folder_id="$2"
    
    for file in $(seq 1 $FILES_PER_FOLDER); do
        size_mb=$((RANDOM % (MAX_SIZE_MB - MIN_SIZE_MB + 1) + MIN_SIZE_MB))
        filename="doc_${folder_id}_${file}.dat"
        filepath="$dir/$filename"
        
        dd if=/dev/zero of="$filepath" bs=1048576 count=$size_mb 2>/dev/null
        echo "File $folder_id-$file created at $(date)" >> "$filepath"
    done
}

create_nested_structure() {
    local base_path="$1"
    local current_level="$2"
    local folder_id="$3"
    
    # Create files in current directory
    create_files "$base_path" "$folder_id"
    echo "  Created $FILES_PER_FOLDER files in $base_path"
    
    # Create nested subdirectories if not at max depth
    if [ $current_level -lt $NESTED_LEVELS ]; then
        for sub in $(seq 1 2); do  # 2 subdirs per level
            sub_folder="level${current_level}_sub${sub}"
            sub_path="$base_path/$sub_folder"
            mkdir -p "$sub_path"
            
            new_folder_id="${folder_id}_${current_level}${sub}"
            create_nested_structure "$sub_path" $((current_level + 1)) "$new_folder_id"
        done
    fi
}

# Create top-level folders with nested structure
for top in $(seq 1 $TOP_FOLDERS); do
    top_folder="department_$top"
    top_path="$BASE_DIR/$top_folder"
    mkdir -p "$top_path"
    echo "Creating nested structure in $top_folder..."
    
    create_nested_structure "$top_path" 1 "d${top}"
done

# Count total files and folders
total_files=$(find "$BASE_DIR" -type f | wc -l)
total_dirs=$(find "$BASE_DIR" -type d | wc -l)

echo "Dataset created successfully!"
echo "Total directories: $total_dirs"
echo "Total files: $total_files"
echo "File size range: ${MIN_SIZE_MB}-${MAX_SIZE_MB}MB"
echo "Nested levels: $NESTED_LEVELS"
echo "Location: $BASE_DIR"