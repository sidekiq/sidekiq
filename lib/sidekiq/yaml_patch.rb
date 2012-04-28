# YAML marshalling of instances can fail in some circumstances,
# e.g. when the instance has a handle to a Proc.  This monkeypatch limits
# the YAML serialization to just AR's internal @attributes hash.
# The paperclip gem litters AR instances with Procs, for instance.
#
# Courtesy of @ryanlecompte https://gist.github.com/007b88ae90372d1a3321
#

if defined?(::ActiveRecord)
  class ActiveRecord::Base
    yaml_as "tag:ruby.yaml.org,2002:ActiveRecord"

    def self.yaml_new(klass, tag, val)
      klass.unscoped.find(val['attributes'][klass.primary_key])
    end

    def to_yaml_properties
      ['@attributes']
    end
  end
end
