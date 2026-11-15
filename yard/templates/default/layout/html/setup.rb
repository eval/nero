# frozen_string_literal: true

# Adds the dark theme on top of YARD's default template (see .yardopts --template-path).
def stylesheets
  super + %w[css/dark.css]
end

def javascripts
  super + %w[js/theme.js]
end
