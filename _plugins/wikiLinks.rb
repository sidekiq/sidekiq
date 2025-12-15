require "kramdown"


# Jekyll module that modifies wiki pages links that refers to wiki pages
# to point to new Jekyll site pages

# WORK IN PROGRESS
module Jekyll

  class WikiLinks < Generator

      # Initialize all variables that will be needed by your new link converter
      def initialize(config = {})

        raise 'Missing wiki configuration. Please configure wiki parameters in _config.yml' unless config['wikiToJekyll']
        @conf = config['wikiToJekyll']
        # this our global var that will be used by our link converter
        $wikiDatas = {'conf'=>config, 'pages'=>Hash.new() }

      end

      # Initialize some variables that will be needed by your new link converter
      # As "site" is not available in initialize we do some work here
      def generate(site)

        # we only change link for pages that are from the wiki
        # our flag is the wiki menu be can also be the page path
        wiki_pages = site.pages.select{ |a| a.data['menu'] == 'wiki' }

        @conf = $wikiDatas['conf']

        wiki_pages.each do |p|

          jekyll_url = '/' + @conf['wikiToJekyll']['wiki_dest'] + '/' + p.basename + '.html'

          $wikiDatas['pages'][p.basename] = {
                                  'possible_uris' => get_possible_uris(p),
                                  'jekyll_url' => jekyll_url
          }

        end
      end

      # return the wiki repository path : https://github.com/userName/repositoryName/wiki
      # @param full boolean full if we need the full url - if false return the absolute path : /userName/repositoryName/wiki
      def getWikiRepositoryUrl(full = true)

        @host = 'https://github.com/'

        if @conf['wikiToJekyll']['wiki_repository_url']
          url = @conf['wikiToJekyll']['wiki_repository_url'].sub('.wiki.git', '') + '/wiki'
        else
          url = @host + @conf['wikiToJekyll']['user_name'] + '/' + @conf['wikiToJekyll']['repository_name'] + '/wiki'
        end

        if full == false
          return url.sub(@host, '')
        else
          return url
        end
      end

      # Generates an array of possible uris for a wiki page
      # total number is :
      #   - number of path possible to generate a link to internal pages in a wiki
      #      [link text](https://github.com/userName/RepositoryName/wiki/Page-name)
      #      [link text](/userName/RepositoryName/wiki/Page-name)
      #      [link text](Page-name)
      # time 2 because both with and w/o trailing slash work
      # time
      #   - the number of page's name forms
      #      page name
      #      page-name
      #      Page-name
      #      Page name
      #      Page-Name
      #      Page Name
      # plus
      #   - two home page pattern
      #      [link text](https://github.com/userName/RepositoryName/wiki)
      #      [link text](/userName/RepositoryName/wiki)
      def get_possible_uris(page)

        @wiki_full_uri = getWikiRepositoryUrl

        @uri = URI.parse(@wiki_full_uri)

        pageName = page.data['wikiPageName'] # Page name

        @patterns = []

        # page name can have different working forms ranging from "page name" to "Page-Name"
        possible_name = [pageName]
        # normalize to lowercase and - as separator
        possible_name += [pageName.gsub(' ', '-').downcase] #page-name
        possible_name += camel_case(pageName, '-')               #Page-name + Page name
        possible_name += camel_caps(pageName, '-')               #Page-Name + Page Name
        possible_name += [pageName.gsub('-', ' ').downcase] #page name

        possible_name.uniq.each do |name|
          @patterns += [
              # possible WORKING internal links patterns that can be found in wiki pages
              # [link text](https://github.com/userName/RepositoryName/wiki/Page-name)
              @wiki_full_uri + '/' + name,
              # [link text](https://github.com/userName/RepositoryName/wiki/Page-name/) trailing slash
              @wiki_full_uri + '/' + name + '/',
              # [link text](/userName/RepositoryName/wiki/Page-name)
              @uri.path + '/' + name,
              # [link text](/userName/RepositoryName/wiki/Page-name/) trailing slash
              @uri.path + '/' + name + '/',
              # [link text](Page-name)
              name
          ]
        end

        # Home page has two other patterns that are the wiki root url with no page name
        # because Home is the default page
        if pageName.downcase == 'home'
          @patterns += [
              # home page direct uris
              # [link text](https://github.com/userName/RepositoryName/wiki)
              @wiki_full_uri,
              # [link text](https://github.com/userName/RepositoryName/wiki) trailing slash
              @wiki_full_uri + '/',
              # [link text](/userName/RepositoryName/wiki)
              @uri.path,
              # [link text](/userName/RepositoryName/wiki) trailing slash
              @uri.path + '/'
          ]
        end

        return @patterns
      end

      # Camel case a string
      # "my sentence" -> "My sentence"
      # @param str splitChr - the character used to split the string - default to space " "
      # @return array[ string joined with space, string joined with - ]
      def camel_case(str, splitChr=" ")
        words = str.downcase.split(splitChr)
        words = [words.shift.capitalize] + words
        return [words.join('-'), words.join(' ')]
      end

      # Camel Caps a string
      # "my sentence" -> "My Sentence"
      # @param str splitChr - the character used to split the string - default to space " "
      # @return array[ string joined with space, string joined with - ]
      def camel_caps(str, splitChr=" ")
        words = str.downcase.split(splitChr).each_with_index.map { |v| v.capitalize }
        return [words.join('-'), words.join(' ')]
      end

  end

end


module Kramdown

  module Converter

    class Html < Base

      # here we override the link html convert
      # we try to detect wiki links and transform them in Jekyll links
      def convert_a(el, indent)

        res  = inner(el, indent)
        @attr = el.attr.dup

        if @attr['href'].start_with?('mailto:')
          mail_addr = @attr['href'][7..-1]
          @attr['href'] = obfuscate('mailto') << ":" << obfuscate(mail_addr)
          res = obfuscate(res) if res == mail_addr

        else ######## OVERRIDE STARTS HERE

          $wikiDatas['pages'].each_value do |page|
            if page['possible_uris'].include?( @attr['href'] )
              Jekyll.logger.info('Changed wiki url', "#{@attr['href']} => #{page['jekyll_url']}")
              @attr['href'] = page['jekyll_url']
            end
          end
          ######## OVERRIDE ENDS HERE
        end

        format_as_span_html(el.type, @attr, res)
      end

    end

  end

end
