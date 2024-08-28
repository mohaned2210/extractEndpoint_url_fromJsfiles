#!/bin/bash

# Default values
max_depth=3
threads=20
input_file=""
output_file="./linkfromJSfile.txt"  # Default output file
# Parse command line arguments
while getopts "d:t:u:o:" opt; do
  case $opt in
    d) max_depth="$OPTARG" ;;
    t) threads="$OPTARG" ;;
    u) input_file="$OPTARG" ;;
    o) output_file="$OPTARG" ;;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

# Check if input file is provided
if [ -z "$input_file" ]; then
    echo "Error: Input file is required."
    echo "Usage: ./extract_link.sh -u /path/to/input/file [-d max_recursion_depth] [-t threads] [-o output_file]"
    exit 1
fi

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist."
    exit 1
fi




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

    # Break down the base URL into its components
    base_path=$(echo "$base_url" | awk -F[/:] '{print $4}')
    protocol=$(echo "$base_url" | awk -F[/:] '{print $1}')
    IFS='/' read -r -a path_parts <<< "${base_url#"$protocol://$base_path"}"

    echo "$links" | sort -u | while IFS= read -r found_link; do
        # Filter out links containing spaces or malformed URLs
        if [[ "$found_link" == *" "* ]] || [[ "$found_link" == *"///"* ]]; then
            continue
        fi

        if [[ $found_link == http://* || $found_link == https://* ]]; then
            # Check if the found link is a subdomain of the base domain and is not the base URL itself
            if is_subdomain "$(extract_domain "$found_link")" "$base_domain" && [ "$found_link" != "$base_url" ]; then
                echo "$found_link" >> "$temp_file"
            fi
        else
            # Possible positions for adding the found endpoint
            if [[ $found_link == /* ]]; then
                # Insert the endpoint at the original base URL
                echo "${base_url}${found_link}" >> "$temp_file"
                
                # Generate URLs by inserting the endpoint at different positions
                for ((i = 0; i <= ${#path_parts[@]}; i++)); do
                    new_url="$protocol://$base_path"
                    for ((j = 0; j < i; j++)); do
                        new_url+="/${path_parts[j]}"
                    done
                    new_url+="${found_link}"
                    echo "$new_url" >> "$temp_file"
                done
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
    
    # Run GoLinkFinder on each link with a timeout of 10 seconds
    golink_output=$(timeout 11 GoLinkFinder -d "$line" 2>/dev/null)
    
    # Debug information for GoLinkFinder
    echo "GoLinkFinder $base_url $(echo "$golink_output" | wc -l)"

    # Process GoLinkFinder output, filter out error messages
    if [ -n "$golink_output" ]; then
        golink_output=$(echo "$golink_output" | grep -v -E 'Error|Usage|invalid input')
        process_links "$base_url" "$golink_output" "$temp_file"
    fi

    # Run LinkFinder on the same link with a timeout of 10 seconds
    cd ~/LinkFinder
    linkfinder_output=$(timeout 11 python3 linkfinder.py -i "$line" -o cli 2>/dev/null)
    
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

# Export functions for use with GNU Parallel
export -f extract_domain
export -f is_subdomain
export -f process_links
export -f process_url

# Function to process URLs recursively
process_recursively() {
    local input="$1"
    local depth="$2"
    local current_output="$temp_dir/depth_${depth}.txt"
    local all_urls="$temp_dir/all_urls.txt"

    echo "Processing at depth $depth"

    # Use GNU Parallel to process URLs concurrently
    parallel -j "$threads" process_url {} "$temp_dir" :::: "$input"

    # Combine all unique temporary files into the current depth output file
    find "$temp_dir" -name "*.tmp" -exec cat {} + | sort -u > "$current_output"

    # Remove specified file types from the output file
    sed -i '/\.css\|\.svg\|\.woff\|\.woff2\|\.woff3\|\.gif\|\.tiff\|\.ttf\|\/x-www-form-urlencoded\|\/image\/png\|\/text\/JavaScript\|\/text\/javascript\|\/text\/css\|\/text\/xml\|\/image\/x-icon/d' "$current_output"

    # Append current depth results to the all URLs file
    cat "$current_output" >> "$all_urls"

    # Sort and remove duplicates from all_urls before proceeding to the next depth
    sort -u "$all_urls" -o "$all_urls"

    # Find new URLs that weren't in the previous depths
    new_urls="$temp_dir/new_urls_${depth}.txt"
    if [ "$depth" -eq 1 ]; then
        cp "$all_urls" "$new_urls"
    else
        comm -23 "$all_urls" "$temp_dir/all_urls_prev.txt" > "$new_urls"
    fi

    # Update the all URLs file for the next iteration
    cp "$all_urls" "$temp_dir/all_urls_prev.txt"

    # If there are new URLs and we haven't reached max depth, continue recursion
    if [ -s "$new_urls" ] && [ "$depth" -lt "$max_depth" ]; then
        process_recursively "$new_urls" $((depth + 1))
    else
        echo "Recursion complete. Final depth: $depth"
        # Copy all discovered URLs to the output file
        cp "$all_urls" "$output_file"
    fi
}

# Start the recursive process
process_recursively "$input_file" 1

# Cleanup
rm -rf "$temp_dir"

echo "Unique filtered links have been saved to: $output_file"
