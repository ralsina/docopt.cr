require "../docopt"
require "tartrazine"

# Colored help and usage through tartrazine, in-process.
#
# This file is opt-in: require "docopt/color" from applications that
# already depend on tartrazine, and the docopt lexer highlights help
# text, usage sections and man-page-ish prose in the terminal. It
# links tartrazine as a library and never shells out.
#
#     require "docopt"
#     require "docopt/color"
#
#     Docopt.use_tartrazine_color  # or use_tartrazine_color("gruvbox-dark")
#     options = Docopt.docopt(doc, ARGV)

module Docopt
  # Install a colorizer that runs text through tartrazine's docopt
  # lexer and terminal formatter, with *theme* (default-dark by
  # default). The usual gating applies: terminals only, NO_COLOR
  # respected.
  def self.use_tartrazine_color(theme : String = "default-dark") : Nil
    lexer = Tartrazine.lexer(name: "docopt")
    formatter = Tartrazine::Ansi.new
    formatter.theme = Tartrazine.theme(theme)
    self.colorizer = ->(text : String) { formatter.format(text, lexer) }
  end
end
