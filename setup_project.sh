#!/bin/bash

# This script creates an Xcode project using the command line
# Compatible with Xcode 15.4

PROJECT_DIR="/Volumes/pookiepants/POOKIEPANTS/AI Code/CascadeProjects/windsurf-project/personal-journal/OpsBrain"
cd "$PROJECT_DIR"

echo "Creating Xcode project for OpsBrain..."

# Use swift package init to create a basic structure, then convert to app
swift package init --type executable --name OpsBrain 2>/dev/null || true

# Clean up the default Package.swift
rm -rf Package.swift Sources Tests

# Now let's just open Xcode and let the user create it manually with guidance
echo ""
echo "============================================"
echo "MANUAL SETUP REQUIRED"
echo "============================================"
echo ""
echo "Please follow these steps:"
echo ""
echo "1. Open Xcode"
echo "2. File → New → Project"
echo "3. Choose: iOS → App"
echo "4. Click Next"
echo "5. Fill in:"
echo "   - Product Name: OpsBrain"
echo "   - Team: (select your team)"
echo "   - Organization Identifier: com.yourname"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "6. Click Next"
echo "7. Save to: $PROJECT_DIR"
echo "   IMPORTANT: Uncheck 'Create Git repository'"
echo "8. Click Create"
echo ""
echo "9. In Xcode, DELETE these auto-generated files:"
echo "   - ContentView.swift (we have our own)"
echo "   - OpsBrainApp.swift (we have our own)"
echo ""
echo "10. Right-click 'OpsBrain' folder → Add Files to OpsBrain"
echo "11. Select ALL folders: Models, Services, Views"
echo "12. Select: OpsBrainApp.swift"
echo "13. UNCHECK 'Copy items if needed'"
echo "14. Click Add"
echo ""
echo "15. Click project → Info tab → Custom iOS Target Properties"
echo "16. Add these keys (click + button):"
echo "    - NSMicrophoneUsageDescription = 'OpsBrain needs microphone access'"
echo "    - NSCalendarsUsageDescription = 'OpsBrain needs calendar access'"
echo "    - NSRemindersUsageDescription = 'OpsBrain needs reminders access'"
echo ""
echo "17. Press Cmd+B to build"
echo "18. Press Cmd+R to run"
echo ""
echo "============================================"
echo ""

# Open Xcode
open -a Xcode

echo "Xcode is opening. Follow the steps above!"
