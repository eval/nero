# frozen_string_literal: true

# The class/method/file lists (shown in the side frame) get the dark theme too.
# YARD copies every file listed here and in the layout's lists into the output.
def stylesheets_full_list
  super + %w[css/dark.css]
end

def javascripts_full_list
  super + %w[js/theme.js]
end
