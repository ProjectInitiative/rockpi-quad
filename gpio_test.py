#!/usr/bin/env python3
import os
import gpiod
import glob

print("Testing GPIO access...")
print(f"SATA_CHIP: {os.environ.get('SATA_CHIP', 'NOT SET')}")
print(f"SATA_LINE_1: {os.environ.get('SATA_LINE_1', 'NOT SET')}")

# List available GPIO chips
chips = glob.glob('/dev/gpiochip*')
print(f"Available GPIO chips: {chips}")

# Try to access each chip using the full path and modern API
for chip_path in chips:
    try:
        # Request a chip handle
        chip = gpiod.Chip(chip_path)
        # Get chip information
        info = chip.get_info()
        print(f"Successfully opened chip {chip_path}: {info.name}")
        print(f"  Label: {info.label}")
        print(f"  Number of lines: {info.num_lines}")
        chip.close()
    except Exception as e:
        print(f"Failed to open chip {chip_path}: {e}")

# Test the specific chip from environment
try:
    sata_chip_num = os.environ.get('SATA_CHIP', '0')
    sata_chip_path = f'/dev/gpiochip{sata_chip_num}' # Construct the full path
    print(f"\nTesting {sata_chip_path}")
    chip = gpiod.Chip(sata_chip_path)
    info = chip.get_info()
    print(f"Success! Chip name: {info.name}, lines: {info.num_lines}")
    chip.close()
except Exception as e:
    print(f"Failed to open {sata_chip_path}: {e}")
