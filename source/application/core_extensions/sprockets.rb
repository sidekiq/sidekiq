require 'uglifier'
require 'handlebars_assets'
require 'sprockets-sass'
require 'sprockets-helpers'
require 'compass'

SPROCKETS = Sprockets::Environment.new
Settings.sprockets['root']       = File.expand_path('../', __FILE__)
Settings.paths['assets'] = Settings.paths.static
Settings.paths['assets'].push Settings.paths.js
Settings.paths['assets'].push Settings.paths.css
Settings.paths['assets'].push Settings.paths.templates
Settings.paths['assets'].push Settings.paths.images
Settings.paths['assets'].push Settings.paths.fonts

# Sprockets.register_engine '.hbs', HandlebarsAssets::TiltHandlebars


def configure_sprockets(opts={})
  searchpaths = []
  %w{ application vendor lib}.each do |dir|
    Settings.sprockets["#{dir}_dir"] = File.join PROJECT_ROOT, dir, '/', Settings.sprockets.assets_prefix
    searchpaths.push Settings.sprockets["#{dir}_dir"]
  end

  # SPROCKETS.css_compressor = Sprockets::Sass::Compressor.new
  SPROCKETS.js_compressor  = Uglifier.new(:mangle => true)

  # setup our paths
  searchpaths.each do |sp|
    Settings.paths['assets'].each do |path|
      SPROCKETS.append_path File.join(sp, path)
    end
  end
  SPROCKETS.append_path HandlebarsAssets.path

  # configure Compass so it can find images
  Compass.add_project_configuration File.expand_path('compass.rb', File.dirname(File.dirname(__FILE__)))

  # configure Sprockets::Helpers
  Sprockets::Helpers.configure do |config|
    config.environment = SPROCKETS
    config.prefix      = Settings.sprockets.assets_prefix
    config.digest      = Settings.sprockets.digest # digests are great for cache busting
    config.manifest    = Sprockets::Manifest.new(
      SPROCKETS,
      File.join(PROJECT_ROOT, Settings.paths.public_folder, Settings.sprockets.assets_prefix, 'manifest.json')
    )

    # clean that thang out
    config.manifest.clean

    static_files     = []

    searchpaths.each do |sp|
      # scoop up the static assets so they can come along for the party
      Settings.paths.static.each do |asset_dir|
        Dir.glob(File.join(sp, asset_dir, '**', '*')).map do |filepath|
          static_files.push filepath.split('/').last
        end
      end
    end

    # write the digested files out to public/assets (makes it so Nginx can serve them directly)
    if opts[:precompile]==true
      config.manifest.clean(0)
      manifest_contents = Settings.sprockets.precompile.concat(static_files)
      config.manifest.compile(manifest_contents)
    end

    # http://www.ruby-doc.org/gems/docs/s/sprockets-2.4.0/Sprockets/Manifest.html
  end
end

