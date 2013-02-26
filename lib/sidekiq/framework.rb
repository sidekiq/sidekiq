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

  def self.hook_framework!(dir)
    case @framework ||= Framework.which_is_it?(dir)
    when :padrino
      require 'sidekiq/frameworks/padrino'
      require File.expand_path("#{dir}/config/boot.rb")
      Sidekiq.hook_padrino!
    when :rails
      require 'rails'
      require 'sidekiq/frameworks/rails'
      require File.expand_path("#{dir}/config/environment.rb")
      ::Rails.application.eager_load!
    # when :sinatra
    end
  end

  def self.framework_root(dir)
    case @framework ||= Framework.which_is_it?(dir)
    when :padrino
      ::Padrino.root if defined?(::Padrino)
    when :rails
      ::Rails.root if defined?(::Rails)
    end
  end
end
