# Check available GPIO chips
ls -la /dev/gpiochip*

# Check GPIO chip information
gpiodetect

# Check permissions
ls -la /dev/gpiochip*

# If you need to find the right chip numbers
for chip in /sys/class/gpio/gpiochip*; do
  echo "Chip: $(basename $chip)"
  cat $chip/label 2>/dev/null || echo "No label"
  cat $chip/ngpio 2>/dev/null || echo "No ngpio info"
  echo "---"
done
