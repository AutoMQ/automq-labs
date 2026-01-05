#!/bin/bash
# Calculate standard deviation from a list of numbers
# Usage: echo "1 2 3 4 5" | ./calculate-std-dev.sh
# Or: ./calculate-std-dev.sh 1 2 3 4 5

set -e

# Read numbers from arguments or stdin
if [ $# -gt 0 ]; then
    numbers="$@"
else
    read -r numbers
fi

# Calculate using Python
python3 << EOF
import sys
import statistics

numbers = [float(x) for x in "$numbers".split()]
if len(numbers) < 2:
    print("0.0")
else:
    std_dev = statistics.stdev(numbers)
    print(f"{std_dev:.2f}")
EOF
