#!/usr/bin/env bash
#
# _TestColors.sh
#
# Usage:
# ./_TestColors.sh
#
# Demo script to test Colors.sh functions
#

if [ -z "${UTILITYPATH}" ]; then
  # UTILITYPATH is unset or empty
  export UTILITYPATH="$(pwd)"
fi

source "${UTILITYPATH}/Colors.sh"

# 1) Test __gradient_print__
echo "===== Gradient Print Test ====="
SMALL_ASCII=$(cat <<'EOF'
--------------------------------------------
 █▀▀ █▀█ █▀▀ █   █▀█    █▀▀ █▀█ █▀█ ▀ ▀█▀ █ 
 █   █ █ █▀▀ █   █▀█    █   █▀█ █ █    █  ▀ 
 ▀▀▀ ▀▀▀ ▀▀▀ ▀▀▀ ▀ ▀    ▀▀▀ ▀ ▀ ▀ ▀    ▀  ▀ 
                                            
 █▀█ █ █ █▀▀    █▀▀ █▀▀ █▀▄ ▀█▀ █▀█ ▀█▀ █▀▀ 
 █▀▀ ▀▄▀ █▀▀    ▀▀█ █   █▀▄  █  █▀▀  █  ▀▀█ 
 ▀    ▀  ▀▀▀    ▀▀▀ ▀▀▀ ▀ ▀ ▀▀▀ ▀    ▀  ▀▀▀ 
--------------------------------------------
  ProxmoxScripts UI                         
  Author: Coela Can't! (coelacant1)         
--------------------------------------------
EOF
)

# Gradient from Purple(128,0,128) to Cyan(0,255,255)
__gradient_print__ "$SMALL_ASCII" 38 2 128 0 255 255


# 2) Test exclude __gradient_print__
LARGE_ASCII=$(cat <<'EOF'
-----------------------------------------------------------------------------------------
                                                                                         
    ██████╗ ██████╗ ███████╗██╗      █████╗      ██████╗ █████╗ ███╗   ██╗████████╗██╗   
   ██╔════╝██╔═══██╗██╔════╝██║     ██╔══██╗    ██╔════╝██╔══██╗████╗  ██║╚══██╔══╝██║   
   ██║     ██║   ██║█████╗  ██║     ███████║    ██║     ███████║██╔██╗ ██║   ██║   ██║   
   ██║     ██║   ██║██╔══╝  ██║     ██╔══██║    ██║     ██╔══██║██║╚██╗██║   ██║   ╚═╝   
   ╚██████╗╚██████╔╝███████╗███████╗██║  ██║    ╚██████╗██║  ██║██║ ╚████║   ██║   ██╗   
    ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝   
                                                                                         
    ██████╗ ██╗   ██║███████╗    ███████╗ ██████╗██████╗ ██║██████╗ ████████╗███████╗    
    ██╔══██╗██║   ██║██╔════╝    ██╔════╝██╔════╝██╔══██╗██║██╔══██╗╚══██╔══╝██╔════╝    
    ██████╔╝██║   ██║█████╗      ███████╗██║     ██████╔╝██║██████╔╝   ██║   ███████╗    
    ██╔═══╝ ╚██╗ ██╔╝██╔══╝      ╚════██║██║     ██╔══██╗██║██╔═══╝    ██║   ╚════██║    
    ██║      ╚████╔╝ ███████╗    ███████║╚██████╗██║  ██║██║██║        ██║   ███████║    
    ╚═╝       ╚═══╝  ╚══════╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝╚═╝        ╚═╝   ╚══════╝    
                                                                                         
-----------------------------------------------------------------------------------------
   User Interface for ProxmoxScripts                                                     
   Author: Coela Can't! (coelacant1)                                                     
-----------------------------------------------------------------------------------------
EOF
)

__gradient_print__ "$LARGE_ASCII" 38 2 128 0 255 255 "█"

echo "=== Testing single_line_solid ==="
__line_rgb__ "Hello from a solid color line" 255 128 0   # orange

echo
echo "=== Testing single___line_gradient__ (left to right) ==="
__line_gradient__ "Left-to-right gradient" 255 0 0 0 255 0  # red => green

echo
echo "=== Testing __gradient_print__ (multiline, top to bottom) ==="
ASCII_ART=$(cat <<'EOF'
Line 1
Line 2
Line 3
EOF
)

# Purple => Teal
__gradient_print__ "$ASCII_ART" 128 0 128 0 255 255

echo
echo "Done. Press Enter to exit."
read -r