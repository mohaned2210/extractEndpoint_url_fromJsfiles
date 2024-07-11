#!/bin/bash

# Check if an argument is provided
if [ $# -eq 0 ]; then
    echo "No input file specified. Usage: ./extract_link.sh /file/to/read"
    exit 1
fi

# Input file path from the argument
input_file="$1"

# Output file path
output_file="./linkfromJSfile.txt"

# Temporary directory for intermediate processing
temp_dir=$(mktemp -d)

# Ensure the output file is empty before starting
> "$output_file"

# Function to extract the domain from a URL
extract_domain() {
    local url="$1"
    echo "$url" | awk -F[/:] '{print $4}'
}

# Function to check if a URL is a subdomain of a base domain
is_subdomain() {
    local url="$1"
    local base_domain="$2"
    [[ "$url" =~ (^|\.)$base_domain$ ]]
}

# Function to process and filter found links
process_links() {
    local base_url="$1"
    local links="$2"
    local temp_file="$3"
    
    # Extract the domain from the base URL
    base_domain=$(extract_domain "$base_url")

    echo "$links" | sort -u | while IFS= read -r found_link; do
        # Filter out links containing spaces
        if [[ "$found_link" == *" "* ]]; then
            continue
        fi
        if [[ $found_link == http://* || $found_link == https://* ]]; then
            # Check if the found link is a subdomain of the base domain and is not the base URL itself
            if is_subdomain "$(extract_domain "$found_link")" "$base_domain" && [ "$found_link" != "$base_url" ]; then
                echo "$found_link" >> "$temp_file"
            fi
        else
            if [[ $found_link == /* ]]; then
                echo "${base_url}${found_link}" >> "$temp_file"
            elif [[ $found_link == ./* ]]; then
                echo "${base_url}/.${found_link:1}" >> "$temp_file"
            else
                echo "${base_url}/${found_link}" >> "$temp_file"
            fi
        fi
    done
}

# Function to process a single URL
process_url() {
    local line="$1"
    local temp_dir="$2"
    local base_url
    local temp_file
    local golink_output
    local linkfinder_output

    # Create a unique temp file name using md5sum
    temp_file="$temp_dir/$(echo "$line" | md5sum | awk '{print $1}').tmp"

    # Extract the base URL
    base_url=$(echo "$line" | awk -F/ '{print $1 "//" $3}')
    
    # Run GoLinkFinder on each link with a timeout of 6 seconds
    golink_output=$(timeout 10 GoLinkFinder -d "$line" 2>/dev/null)
    
    # Debug information for GoLinkFinder
    echo "GoLinkFinder $base_url $(echo "$golink_output" | wc -l)"

    # Process GoLinkFinder output, filter out error messages
    if [ -n "$golink_output" ]; then
        golink_output=$(echo "$golink_output" | grep -v -E 'Error|Usage|invalid input')
        process_links "$base_url" "$golink_output" "$temp_file"
    fi

    # Run LinkFinder on the same link with a timeout of 6 seconds
    cd ~/LinkFinder
    linkfinder_output=$(timeout 10 python3 linkfinder.py -i "$line" -o cli 2>/dev/null)
    
    # Debug information for LinkFinder
    echo "LinkFinder $base_url $(echo "$linkfinder_output" | wc -l)"
    
    # Process LinkFinder output, filter out error messages
    if [ -n "$linkfinder_output" ]; then
        linkfinder_output=$(echo "$linkfinder_output" | grep -v -E 'Error|Usage|invalid input')
        process_links "$base_url" "$linkfinder_output" "$temp_file"
    fi

    # Add a blank line for separation between different original links
    echo "" >> "$temp_file"
}

export -f process_links
export -f process_url
export -f extract_domain
export -f is_subdomain

# Use GNU Parallel to process URLs concurrently, creating a unique temp file for each job
cat "$input_file" | parallel -j 20 process_url {} "$temp_dir"

# Combine all unique temporary files into the final output file
cat "$temp_dir"/*.tmp | sort -u > "$output_file"

# Remove specified file types from the output file
sed -i '/\.css\|\.svg\|\.woff\|\.woff2\|\.woff3\|\.gif\|\.tiff\|\.ttf\|\/image\/png\|\/text\/css\|\/image\/x-icon/d' "$output_file"

# Cleanup
rm -rf "$temp_dir"

echo "Unique filtered links have been saved to: $output_file"
