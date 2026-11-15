# frozen_string_literal: true

# Generates assets/banner.svg (the README header): ruby yard/banner.rb assets/banner.svg
# Laurel leaves are computed along two arcs around the flame.
cx, cy, r = 200.0, 192.0, 112.0
leaves = []
[-1, 1].each do |side| # left and right branch
  # from the bottom (90°) up to near the top (-62°), 11 leaves
  10.times do |i|
    t = i / 9.0
    deg = 68 - t * 126 # 68 → -58 (degrees from +x, y down): bottom (just off centre) up to the top
    a = deg * Math::PI / 180
    x = cx + side * r * Math.cos(a)
    y = cy + r * Math.sin(a)
    tangent = deg - 90                              # direction along the arc (upwards)
    tilt = 28                                       # leaves point outward/up
    rot = (side == 1) ? tangent + 180 - tilt : 180 - (tangent + 180 - tilt)
    size = 1.0 - t * 0.35
    [-1, 1].each do |out| # pair of leaves: outer and inner
      off = out * 9 * size
      lx = x + side * off * Math.cos(a)
      ly = y + off * Math.sin(a)
      lrot = rot + side * out * 24
      leaves << %(<ellipse cx="#{lx.round(1)}" cy="#{ly.round(1)}" rx="#{(17 * size).round(1)}" ry="#{(6.5 * size).round(1)}" transform="rotate(#{lrot.round(1)} #{lx.round(1)} #{ly.round(1)})"/>)
    end
  end
end
stems = [-1, 1].map do |side|
  pts = (0..20).map do |i|
    deg = 68 - (i / 20.0) * 126
    a = deg * Math::PI / 180
    "#{(cx + side * r * Math.cos(a)).round(1)},#{(cy + r * Math.sin(a)).round(1)}"
  end
  %(<polyline points="#{pts.join(" ")}" fill="none" stroke="#b8862b" stroke-width="3" stroke-linecap="round"/>)
end

mono = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'JetBrains Mono', monospace"
sans = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

svg = <<~SVG
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 380" width="1280" height="380" role="img" aria-labelledby="title desc">
    <title id="title">Nero</title>
    <desc id="desc">A flame in a golden laurel wreath next to the name Nero, declarative YAML-tags, and a sample config using !env, !env/integer and !ip.</desc>
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#1d1410"/>
        <stop offset="0.55" stop-color="#2a1711"/>
        <stop offset="1" stop-color="#3b1a10"/>
      </linearGradient>
      <radialGradient id="glow" cx="200" cy="200" r="190" gradientUnits="userSpaceOnUse">
        <stop offset="0" stop-color="#ff8a2a" stop-opacity="0.35"/>
        <stop offset="1" stop-color="#ff8a2a" stop-opacity="0"/>
      </radialGradient>
      <linearGradient id="flame" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#ffd76e"/>
        <stop offset="0.45" stop-color="#ff8a1f"/>
        <stop offset="1" stop-color="#e2381b"/>
      </linearGradient>
      <linearGradient id="core" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#fff6cf"/>
        <stop offset="1" stop-color="#ffbe45"/>
      </linearGradient>
      <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#f3c65d"/>
        <stop offset="1" stop-color="#b8862b"/>
      </linearGradient>
    </defs>

    <rect width="1280" height="380" rx="20" fill="url(#bg)"/>
    <circle cx="200" cy="200" r="190" fill="url(#glow)"/>

    <!-- laurel wreath -->
    #{stems.join("\n  ")}
    <g fill="url(#gold)">
      #{leaves.join("\n    ")}
    </g>

    <!-- flame -->
    <path fill="url(#flame)" d="M 200 96 C 236 138, 266 172, 262 220 C 258 262, 232 288, 200 288 C 168 288, 142 262, 140 222 C 138 186, 156 160, 172 138 C 174 168, 184 186, 196 192 C 188 160, 186 128, 200 96 Z"/>
    <path fill="url(#core)" d="M 202 174 C 222 200, 236 218, 232 244 C 229 266, 216 276, 200 276 C 184 276, 170 264, 170 244 C 170 226, 180 214, 188 204 C 190 218, 196 226, 204 228 C 198 210, 196 192, 202 174 Z"/>

    <!-- sparks -->
    <g fill="#ffb347">
      <circle cx="214" cy="74" r="3.5" opacity="0.9"/>
      <circle cx="188" cy="60" r="2.5" opacity="0.7"/>
      <circle cx="224" cy="44" r="2" opacity="0.6"/>
      <circle cx="196" cy="30" r="1.6" opacity="0.5"/>
    </g>

    <!-- name and tagline -->
    <text x="350" y="200" font-family="#{sans}" font-size="124" font-weight="700" fill="#fbeee0" letter-spacing="2">Nero</text>
    <text x="354" y="252" font-family="#{sans}" font-size="30" fill="#f0b98a">Declarative YAML-tags</text>
    <text x="354" y="290" font-family="#{sans}" font-size="22" fill="#b89480">env-vars, coercion, refs and more</text>

    <!-- sample config -->
    <g transform="translate(728 78)">
      <rect width="516" height="226" rx="14" fill="#120c09" fill-opacity="0.75" stroke="#4a2f22"/>
      <circle cx="26" cy="24" r="6" fill="#e2381b"/>
      <circle cx="46" cy="24" r="6" fill="#ff8a1f"/>
      <circle cx="66" cy="24" r="6" fill="#ffd76e"/>
      <text x="100" y="29" font-family="#{mono}" font-size="15" fill="#8a6c5c">config/app.yml</text>
      <g font-family="#{mono}" font-size="21" xml:space="preserve">
        <text x="26" y="80" fill="#f4e6d8">production:</text>
        <text x="26" y="116" fill="#f4e6d8">  secret: <tspan fill="#ff9a3c">!env</tspan> SECRET</text>
        <text x="26" y="152" fill="#f4e6d8">  port:   <tspan fill="#ff9a3c">!env/integer</tspan> [PORT, 3000]</text>
        <text x="26" y="188" fill="#f4e6d8">  admins: <tspan fill="#ff9a3c">!ip</tspan> 10.0.0.0/8</text>
      </g>
    </g>
  </svg>
SVG
File.write(ARGV[0], svg)
