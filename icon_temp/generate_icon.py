import sys

svg_content = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#4B9AFA"/>
      <stop offset="100%" stop-color="#1A68D6"/>
    </linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="15" stdDeviation="15" flood-color="#000000" flood-opacity="0.25"/>
    </filter>
  </defs>
  <!-- Background Squircle (macOS Style) -->
  <rect width="820" height="820" x="102" y="102" rx="185" fill="url(#bg)" filter="url(#shadow)"/>
  
  <!-- Envelope Base -->
  <rect width="520" height="360" x="252" y="332" rx="32" fill="#FFFFFF" filter="url(#shadow)"/>
  
  <!-- Envelope Flap (Top triangle part) -->
  <path d="M252 364 C252 346 266 332 284 332 L740 332 C758 332 772 346 772 364 L512 532 L252 364 Z" fill="#E8F1FF"/>
  
  <!-- Envelope outline/crease -->
  <path d="M252 364 L512 532 L772 364" stroke="#1A68D6" stroke-width="24" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</svg>
"""

with open("icon_temp/icon.svg", "w") as f:
    f.write(svg_content)
