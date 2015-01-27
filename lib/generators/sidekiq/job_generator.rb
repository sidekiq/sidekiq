require 'rails/generators/named_base'

module Sidekiq
  module Generators # :nodoc:
    class JobGenerator < ::Rails::Generators::NamedBase # :nodoc:
      desc 'This generator creates a Sidekiq Job in app/jobs and a corresponding test'

      check_class_collision suffix: 'Job'

      def self.default_generator_root
        File.dirname(__FILE__)
      end

      def create_job_file
        template 'job.rb.erb', File.join('app/jobs', class_path, "#{file_name}_job.rb")
      end

      def create_test_file
        if defined?(RSpec)
          create_job_spec
        else
          create_job_test
        end
      end

      private

      def create_job_spec
        template_file = File.join(
            'spec/jobs',
            class_path,
            "#{file_name}_job_spec.rb"
        )
        template 'job_spec.rb.erb', template_file
      end

      def create_job_test
        template_file = File.join(
            'test/jobs',
            class_path,
            "#{file_name}_job_test.rb"
        )
        template 'job_test.rb.erb', template_file
      end


    end
  end
end
