require 'yaml'
require 'uri'

# use Jekyll configuration file
CONFIG = YAML.load_file("_config.yml")

task :default => :build_dev

# == Helpers ===========================================
def check_configuration
  if CONFIG['wikiToJekyll'].nil? or CONFIG['wikiToJekyll'].empty?
    raise "Please set your configuration in _config.yml. See the readme."
  end
end

# shortener to get configuration parameter
def g(key)
  CONFIG['wikiToJekyll'][key]
end

def get_wiki_repository_url
  derived_url = 'https://github.com/' + g('user_name') + '/' + g('repository_name') + '.wiki.git'
  g('wiki_repository_url') || derived_url
end

# IMPORTANT ++++++++++++++++
# you submodule MUST be added with the https:// scheme
# git add submoudle https://github.com/userName/RepositoryName.wiki.git
# otherwise you will have github errors
def update_wiki_submodule
  cd g('wiki_source') do
    pullCommand = 'git pull origin master'
    puts "Updating wiki submodule"
    output = `#{pullCommand}`

    if output.include? 'Already up-to-date'
      abort("No update necessary") # exit
    end
  end
end

def clean_wiki_folders
  if File.exist?(g('wiki_dest'))
    puts "remove older wiki pages"

    Dir.glob("#{g('wiki_dest')}/*.md") do |wikiPage|
      puts "removing #{g('wiki_dest')}"
      rm_rf wikiPage
    end
  else
    puts "create the dest dir for wiki pages"
    FileUtils.mkdir(g('wiki_dest'))
  end
end

def copy_wiki_pages
  # here we only glob page beginning by a letter
  # no _footer.md or thing like this
  Dir.glob("#{g('wiki_source')}/[A-Za-z]*.md") do |wikiPage|

    wikiPageFileName = File.basename(wikiPage).gsub(" ","-")
    wikiPagePath     = File.join("#{g('wiki_dest')}", wikiPageFileName)

    # remove extension
    wikiPageName    = wikiPageFileName.sub(/.[^.]+\z/,'')
    wikiPageTitle   = wikiPageName.gsub("-"," ")
    fileContent      = File.read(wikiPage)

    puts "generating #{wikiPagePath}"

    # write the new file with yaml front matter
    open(wikiPagePath, 'w') do |newWikiPage|
      newWikiPage.puts "---"
      newWikiPage.puts "layout: wiki"
      newWikiPage.puts "title: #{wikiPageTitle}"
      # used to transform links
      newWikiPage.puts "wikiPageName: #{wikiPageName}"
      # used to generate a wiki specific menu. see readme
      newWikiPage.puts "menu: wiki"
      newWikiPage.puts "syncAt: #{Time.now.iso8601}"
      newWikiPage.puts "---"
      newWikiPage.puts ""
      newWikiPage.puts fileContent
    end
  end
end

def build_jekyll
  system 'jekyll build'
end

def deploy
  puts "deploying"
  system "git add -A"
  message = "Site wiki update #{Time.now.utc}"
  puts "\n## Committing: #{message}"
  system "git commit -m \"#{message}\""
  puts "\n## Pushing website"
  system "git push #{g('deploy_remote')} #{g('deploy_branch')}"
  puts "\n## Github Pages deploy complete"
end

# synch repository wiki pages with Jekyll
# needs a public wiki
task :wiki do |t|
  check_configuration
  update_wiki_submodule
  Rake::Task[:wikibuild].execute
  if g('commit_and_push') == true
      deploy
  end
  puts "Wiki synchronisation success !"
end

# add wiki as a submodule
task :wikisub do |t|
  puts "adding wiki as submodule"
  check_configuration
  wiki_repository = get_wiki_repository_url
  command = 'git submodule add ' + wiki_repository + ' ' + g('wiki_source')
  command += ' && git submodule init'
  command += ' && git submodule update'
  puts 'command : ' + command

  output = `#{command}`

  if output.include? 'failed'
    puts "========== ERROR"
    puts output
    puts "========== ERROR"
    abort("submodule add failed : verify you configuration and that you wiki is public") # exit
  end

  puts "wiki submodule OK"
end


task :wikibuild do |t|
  puts 'rake:wikibuild'
  clean_wiki_folders
  copy_wiki_pages
  build_jekyll
end

task :build_dev do |t|
  puts "Building with dev parameters"
  sh 'jekyll build --config _config.yml,_config_dev.yml --trace'
end

task :prod do |t|
  puts "Building with production parameters"
  sh 'jekyll build'
end

task :deploy do |t|
  deploy
end
