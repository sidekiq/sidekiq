module Sidekiq
  module Framework
    def self.which_is_it?(path='.')
      if is_padrino?(path)
        :padrino
      elsif is_rails?(path)
        :rails
      elsif is_sinatra?(path)
        :sinatra
      end
    end

    def self.hook!(path)
      case @framework ||= which_is_it?(path)
      when :padrino
        require 'sidekiq/frameworks/padrino'
        require File.expand_path("#{path}/config/boot.rb")
        Sidekiq::Framework::Padrino.hook!
      when :rails
        require 'rails'
        require 'sidekiq/frameworks/rails'
        require File.expand_path("#{path}/config/environment.rb")
        ::Rails.application.eager_load!
      # when :sinatra
      end
    end

    def self.root(path)
      case @framework ||= which_is_it?(path)
      when :padrino
        ::Padrino.root if defined?(::Padrino)
      when :rails
        ::Rails.root if defined?(::Rails)
      end
    end

    def self.root?(path)
      is_padrino?(path) || is_rails?(path)
    end

    def self.is_padrino?(path='.')
      find :padrino, files(path, [File.join('config', 'boot.rb')])
    end

    def self.is_rails?(path='.')
      find :rails, files(path, [File.join('config', 'application.rb')])
    end

    def self.is_sinatra?(path='.')
      find :sinatra, files(path, ['*.rb'])
    end

    private
      def self.find(framework, files=[])
        files.each do |file|
          if File.exists?(file)
            return true if File.read(file).index(/#{framework}/i)
          end
        end
        return false
      end

      def self.files(path, list)
        list.map { |f| Dir[File.join(path, f)] }.flatten
      end
  end
end
