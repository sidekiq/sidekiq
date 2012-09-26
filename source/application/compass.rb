# Require any additional compass plugins here.

# Set this to the root of your project when deployed:

project_path         = Settings.sprockets['application_dir']

images_dir           = Settings.paths.images
sass_dir             = Settings.paths.css
css_dir              = Settings.paths.css
javascripts_dir      = Settings.paths.js
fonts_dir            = Settings.paths.fonts

# You can select your preferred output style here (can be overridden via the command line):
output_style = :compressed

# To enable relative paths to assets via compass helper functions. Uncomment:
relative_assets = true

# To disable debugging comments that display the original location of your selectors. Uncomment:
line_comments = false


# If you prefer the indented syntax, you might want to regenerate this
# project again passing --syntax sass, or you can uncomment this:
# preferred_syntax = :sass
# and then run:
# sass-convert -R --from scss --to sass sass scss && rm -rf sass && mv scss sass
