#!/bin/sh
# filepath: /home/jmservera/source/private-webapp/scripts/generate-sid.sh

generate_sid() {
    # Remove hyphens and extract parts in correct order
    guid_clean=$(echo "$1" | tr -d '-')
    
    # Extract and reorder parts directly
    p1=$(expr substr "$guid_clean" 7 2)$(expr substr "$guid_clean" 5 2)$(expr substr "$guid_clean" 3 2)$(expr substr "$guid_clean" 1 2)
    p2=$(expr substr "$guid_clean" 11 2)$(expr substr "$guid_clean" 9 2)
    p3=$(expr substr "$guid_clean" 15 2)$(expr substr "$guid_clean" 13 2)
    p4=$(expr substr "$guid_clean" 17 16)
    
    # Combine, convert to uppercase and add prefix
    echo "0x$(echo "${p1}${p2}${p3}${p4}" | tr '[:lower:]' '[:upper:]')"
}

# Check if an argument was provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <guid>"
    echo "Example: $0 01234567-89ab-cdef-0123-456789abcdef"
    exit 1
fi

# Generate and display the SID
generate_sid "$1"